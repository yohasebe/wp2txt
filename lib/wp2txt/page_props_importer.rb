# frozen_string_literal: true

require "sqlite3"
require "time"
require "digest"
require_relative "sql_dump_reader"
require_relative "version"

module Wp2txt
  # Imports Wikidata IDs, disambiguation flags, and default sort keys
  # from the official page_props dump into the metadata index, as
  # page_properties. Like langlinks, the dump must carry the same
  # date as the index: IDs are only meaningful for the pages they came with.
  class PagePropsImporter
    BATCH_SIZE = 50_000

    # (pp_page,'pp_propname','pp_value',pp_sortkey) — string classes accept
    # escaped quotes and backslashes; sortkey is NULL or a number
    TUPLE_REGEX = /\((\d+),'((?:[^'\\]|\\.)*)','((?:[^'\\]|\\.)*)',(?:NULL|[-+.\deE]+)\)/
    QID_REGEX = /\AQ\d+\z/

    def initialize(db_path)
      @db_path = db_path
    end

    # "jawiki-20260901-page_props.sql.gz" => "jawiki-20260901"
    def self.dump_name_of(path)
      File.basename(path)[/\A[a-z0-9_\-]+?-\d{8}/]
    end

    # @return [Hash] { status: :imported | :already_imported, row_count:, provenance: }
    def import!(source_path, force: false)
      raise ArgumentError, "page_props file not found: #{source_path}" unless File.exist?(source_path)

      db = SQLite3::Database.new(@db_path)
      db.busy_timeout = 5000
      dump_name = metadata_value(db, "dump_name")
      raise ArgumentError, "metadata index is not built: #{@db_path}" unless dump_name

      source_dump = self.class.dump_name_of(source_path)
      unless source_dump && source_dump == dump_name
        raise ArgumentError,
              "dump version mismatch: the metadata index is #{dump_name} but the page_props file is " \
              "#{source_dump || File.basename(source_path)} (versions must match; there is no override)"
      end

      if !force && (existing = imported_at(db))
        return { status: :already_imported, imported_at: existing,
                 row_count: db.get_first_value("SELECT COUNT(*) FROM page_properties").to_i, provenance: read_provenance(db) }
      end

      db.execute("DROP TABLE IF EXISTS page_qids") # replace the unreleased QID-only schema
      db.execute("DROP TABLE IF EXISTS page_properties")
      # A failed load must leave the index looking "not imported"
      db.execute("DELETE FROM metadata WHERE key LIKE 'page\\_props\\_%' ESCAPE '\\'")
      db.execute(<<~SQL)
        CREATE TABLE page_properties (
          page_id INTEGER PRIMARY KEY,
          qid TEXT,
          disambiguation INTEGER NOT NULL DEFAULT 0,
          sort_key TEXT
        )
      SQL

      rows_seen = 0
      skipped_invalid = 0
      batch = []
      flush = lambda do
        db.transaction do
          stmt = db.prepare(<<~SQL)
            INSERT INTO page_properties (page_id, qid, disambiguation, sort_key) VALUES (?, ?, ?, ?)
            ON CONFLICT(page_id) DO UPDATE SET
              qid = COALESCE(excluded.qid, page_properties.qid),
              disambiguation = MAX(excluded.disambiguation, page_properties.disambiguation),
              sort_key = COALESCE(excluded.sort_key, page_properties.sort_key)
          SQL
          batch.each { |row| stmt.execute(row) }
          stmt.close
        end
        batch.clear
      end

      SqlDumpReader.each_insert_line(source_path, "page_props") do |line|
        line.scan(TUPLE_REGEX) do |page, name, value|
          rows_seen += 1
          row = [page.to_i, nil, 0, nil]
          case name
          when "wikibase_item"
            qid = SqlDumpReader.unescape(value)
            next unless QID_REGEX.match?(qid)

            row[1] = qid.force_encoding(Encoding::UTF_8)
          when "disambiguation"
            row[2] = 1
          when "defaultsort"
            key = SqlDumpReader.unescape(value).force_encoding(Encoding::UTF_8)
            unless key.valid_encoding?
              skipped_invalid += 1
              next
            end
            row[3] = key
          else
            next
          end
          batch << row
          flush.call if batch.size >= BATCH_SIZE
        end
      end
      flush.call unless batch.empty?

      if rows_seen.zero?
        raise Wp2txt::Error, "no page_props rows found in #{File.basename(source_path)}; " \
                             "the file may be empty or in an unrecognized format"
      end

      counts = db.get_first_row("SELECT COUNT(*), COUNT(qid), SUM(disambiguation), COUNT(sort_key) FROM page_properties")
      row_count = counts[0]
      stamp_provenance(db, source_path, counts, skipped_invalid)
      { status: :imported, row_count: row_count, provenance: read_provenance(db) }
    ensure
      db&.close
    end

    private

    def metadata_value(db, key)
      db.get_first_value("SELECT value FROM metadata WHERE key = ?", [key])
    rescue SQLite3::Exception
      nil
    end

    def imported_at(db)
      table = db.get_first_value("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'page_properties'")
      table && metadata_value(db, "page_props_imported_at")
    end

    def stamp_provenance(db, source_path, counts, skipped_invalid)
      values = {
        page_props_source: File.basename(source_path),
        page_props_source_size: File.size(source_path),
        page_props_source_sha256: Digest::SHA256.file(source_path).hexdigest,
        page_props_imported_at: Time.now.utc.iso8601,
        page_props_wp2txt_version: Wp2txt::VERSION,
        page_props_page_count: counts[0],
        page_props_qid_count: counts[1],
        page_props_disambiguation_count: counts[2].to_i,
        page_props_sort_key_count: counts[3],
        page_props_skipped_invalid_sort_keys: skipped_invalid
      }
      stmt = db.prepare("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)")
      values.each { |k, v| stmt.execute([k.to_s, v.to_s]) }
      stmt.close
    end

    def read_provenance(db)
      {
        source: metadata_value(db, "page_props_source"),
        source_size: metadata_value(db, "page_props_source_size").to_i,
        source_sha256: metadata_value(db, "page_props_source_sha256"),
        imported_at: metadata_value(db, "page_props_imported_at"),
        imported_with: metadata_value(db, "page_props_wp2txt_version"),
        page_count: metadata_value(db, "page_props_page_count").to_i,
        qid_count: metadata_value(db, "page_props_qid_count").to_i,
        disambiguation_count: metadata_value(db, "page_props_disambiguation_count").to_i,
        sort_key_count: metadata_value(db, "page_props_sort_key_count").to_i,
        skipped_invalid_sort_keys: metadata_value(db, "page_props_skipped_invalid_sort_keys").to_i
      }
    end
  end
end
