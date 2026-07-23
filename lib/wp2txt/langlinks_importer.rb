# frozen_string_literal: true

require "sqlite3"
require "set"
require "time"
require "zlib"
require_relative "metadata_index"
require_relative "version"

module Wp2txt
  # Imports the official langlinks dump ({lang}wiki-{date}-langlinks.sql.gz,
  # MySQL dump format) into the Tier 1 metadata DB as a `langlinks` table
  # (ll_from = source page_id, ll_lang = target language, ll_title = title in
  # the target edition, normalized like pages.title).
  #
  # Version pinning is the reason this feature exists: the langlinks file's
  # dump name (e.g. jawiki-20260701) MUST equal the metadata DB's dump_name;
  # a mismatch is rejected with no override.
  class LanglinksImporter
    # Rows inserted per transaction (index creation is deferred until after
    # the load, so inserts stay fast)
    BATCH_SIZE = 10_000

    # Post-import sanity check (design doc §1.6): per target language, join a
    # random sample of ll_title values against the target language's local
    # meta DB (when installed) and report the match rate; a low rate signals
    # a title-normalization mismatch
    SANITY_SAMPLE_SIZE = 1000
    SANITY_WARN_THRESHOLD = 0.9

    INSERT_PREFIX = /\A\s*INSERT\s+INTO\s+`langlinks`\s+VALUES\s+/i

    # MySQL backslash escapes inside mysqldump string literals
    UNESCAPES = {
      "0" => "\0", "'" => "'", '"' => '"', "b" => "\b", "n" => "\n",
      "r" => "\r", "t" => "\t", "Z" => "\x1A", "\\" => "\\"
    }.freeze

    def initialize(db_path, cache_dir: nil)
      @db_path = db_path
      @cache_dir = cache_dir
    end

    # "jawiki-20260701-langlinks.sql.gz" => "jawiki-20260701" (same extraction
    # rule as the dump_name recorded in the metadata DB)
    def self.dump_name_of(path)
      File.basename(path)[/\A[a-z0-9_\-]+?-\d{8}/]
    end

    # @param source_path [String] langlinks .sql or .sql.gz file
    # @param langs [Array<String>, nil] target languages to import (nil = all)
    # @param force [Boolean] drop and re-import an existing langlinks table
    # @param progress [Proc, nil] called with the running row count per batch
    # @return [Hash] { status: :imported | :already_imported, ... }
    def import!(source_path, langs: nil, force: false, progress: nil)
      raise ArgumentError, "langlinks file not found: #{source_path}" unless File.exist?(source_path)

      db = open_db
      dump_name = metadata_value(db, "dump_name")
      raise ArgumentError, "metadata index is not built: #{@db_path}" unless dump_name

      source_dump = self.class.dump_name_of(source_path)
      unless source_dump && source_dump == dump_name
        raise ArgumentError,
              "dump version mismatch: the metadata index is #{dump_name} but the langlinks file is " \
              "#{source_dump || File.basename(source_path)} (versions must match; there is no override)"
      end

      if !force && (existing = imported_at(db))
        return { status: :already_imported, imported_at: existing,
                 row_count: db.get_first_value("SELECT COUNT(*) FROM langlinks").to_i }
      end

      lang_filter = langs && Set.new(langs)

      db.execute("DROP TABLE IF EXISTS langlinks")
      # Clear stale provenance immediately: if the load below fails midway,
      # the DB must be left as "not imported" (partial table only), so the
      # next non-force run re-imports instead of reporting a stale success
      db.execute("DELETE FROM metadata WHERE key LIKE 'langlinks\\_%' ESCAPE '\\'")
      db.execute(<<~SQL)
        CREATE TABLE langlinks (
          ll_from  INTEGER NOT NULL,
          ll_lang  TEXT    NOT NULL,
          ll_title TEXT    NOT NULL
        )
      SQL

      row_count = 0
      batch = []
      flush = lambda do
        db.transaction do
          stmt = db.prepare("INSERT INTO langlinks (ll_from, ll_lang, ll_title) VALUES (?, ?, ?)")
          batch.each { |row| stmt.execute(row) }
          stmt.close
        end
        row_count += batch.size
        progress&.call(row_count)
        batch.clear
      end

      skipped_invalid = each_source_row(source_path) do |ll_from, ll_lang, ll_title|
        next if lang_filter && !lang_filter.include?(ll_lang)

        batch << [ll_from, ll_lang, MetadataIndex.normalize_title(ll_title)]
        flush.call if batch.size >= BATCH_SIZE
      end
      flush.call unless batch.empty?

      # Indexes are created after the load, not before (insert speed)
      db.execute("CREATE INDEX idx_langlinks_from ON langlinks(ll_from, ll_lang)")
      db.execute("CREATE INDEX idx_langlinks_lang_title ON langlinks(ll_lang, ll_title)")

      stamp_provenance(db, source_path, langs, row_count, skipped_invalid)

      { status: :imported, row_count: row_count, skipped_invalid: skipped_invalid,
        provenance: read_provenance(db),
        sanity: sanity_check(db, dump_name) }
    ensure
      db&.close
    end

    private

    def open_db
      db = SQLite3::Database.new(@db_path)
      db.busy_timeout = 5000
      db
    end

    def metadata_value(db, key)
      db.get_first_value("SELECT value FROM metadata WHERE key = ?", [key])
    rescue SQLite3::Exception
      nil
    end

    # Non-nil only when a previous completed import is still in place
    def imported_at(db)
      table = db.get_first_value(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'langlinks'"
      )
      table && metadata_value(db, "langlinks_imported_at")
    end

    def stamp_provenance(db, source_path, langs, row_count, skipped_invalid)
      values = {
        langlinks_source: File.basename(source_path),
        langlinks_source_size: File.size(source_path),
        langlinks_imported_at: Time.now.utc.iso8601,
        langlinks_wp2txt_version: Wp2txt::VERSION,
        langlinks_lang_filter: langs.nil? ? "all" : langs.join(","),
        langlinks_row_count: row_count,
        langlinks_skipped_invalid: skipped_invalid
      }
      stmt = db.prepare("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)")
      values.each { |k, v| stmt.execute([k.to_s, v.to_s]) }
      stmt.close
    end

    def read_provenance(db)
      {
        source: metadata_value(db, "langlinks_source"),
        source_size: metadata_value(db, "langlinks_source_size").to_i,
        imported_at: metadata_value(db, "langlinks_imported_at"),
        imported_with: metadata_value(db, "langlinks_wp2txt_version"),
        lang_filter: metadata_value(db, "langlinks_lang_filter"),
        row_count: metadata_value(db, "langlinks_row_count").to_i,
        skipped_invalid: metadata_value(db, "langlinks_skipped_invalid").to_i
      }
    end

    # Post-import sanity check (§1.6): for each target language whose meta DB
    # is installed locally, draw a random sample and report how many ll_title
    # values exist in that DB's pages.title
    def sanity_check(db, dump_name)
      reports = []
      main_date = dump_name[/\d{8}\z/]
      db.execute("SELECT DISTINCT ll_lang FROM langlinks ORDER BY ll_lang").flatten.each do |lang|
        candidates = MetadataIndex.cached_candidates(lang, cache_dir: @cache_dir)
        next if candidates.empty? # target edition not installed locally: skip

        pick = candidates.find { |c| c[:dump_name].to_s.end_with?(main_date.to_s) } || candidates.first
        sample = db.execute(
          "SELECT ll_title FROM langlinks WHERE ll_lang = ? ORDER BY RANDOM() LIMIT ?",
          [lang, SANITY_SAMPLE_SIZE]
        ).flatten
        next if sample.empty?

        other = SQLite3::Database.new(pick[:db_path], readonly: true)
        begin
          stmt = other.prepare("SELECT 1 FROM pages WHERE title = ? LIMIT 1")
          matched = sample.count { |title| stmt.execute(title).any? }
          stmt.close
        ensure
          other.close
        end

        rate = matched.to_f / sample.size
        reports << { lang: lang, sampled: sample.size, matched: matched,
                     match_rate: rate.round(3), against: pick[:dump_name],
                     warning: rate < SANITY_WARN_THRESHOLD }
      end
      reports
    end

    # ------------------------------------------------------------------
    # Streaming MySQL dump parser
    # ------------------------------------------------------------------

    # Yield [ll_from, ll_lang, ll_title] for every VALID tuple of every
    # INSERT INTO `langlinks` statement, streaming (the dump is never
    # loaded into memory whole). Handles .sql.gz and plain .sql.
    # @return [Integer] number of tuples skipped for invalid UTF-8
    #
    # Tuple extraction is regex-based: a hand-rolled line[i] character-index
    # loop is O(n²) on multibyte (UTF-8 code-range) lines, and real extended
    # INSERT lines are MB-scale with multilingual titles — the regex engine
    # scans at C speed and is O(n) regardless of encoding.
    #
    # Lines are read as BINARY: ll_title is VARBINARY in MySQL and real dumps
    # contain historically corrupted bytes, so regex matching on UTF-8-tagged
    # strings can raise "invalid byte sequence". The patterns are ASCII-only,
    # so they run on byte strings without encoding checks; captures are then
    # tagged UTF-8 and validated — a garbled title could never join
    # pages.title anyway, so such rows are skipped (and counted), not scrubbed.
    def each_source_row(source_path)
      io = if source_path.end_with?(".gz")
             # GzipReader ignores set_encoding; the encoding must be given
             # at open time (lines must come out as BINARY — see below)
             Zlib::GzipReader.open(source_path, encoding: Encoding::BINARY.to_s)
           else
             File.open(source_path, "rb")
           end

      skipped = 0
      begin
        io.each_line do |line|
          next unless INSERT_PREFIX.match?(line)

          line.scan(TUPLE_REGEX) do |ll_from, ll_lang, ll_title|
            lang = unescape_mysql(ll_lang).force_encoding(Encoding::UTF_8)
            title = unescape_mysql(ll_title).force_encoding(Encoding::UTF_8)
            unless lang.valid_encoding? && title.valid_encoding?
              skipped += 1
              next
            end

            yield ll_from.to_i, lang, title
          end
        end
      ensure
        io.close
      end
      skipped
    end

    # One extended-INSERT tuple: (123,'lang','Title'). The string classes
    # [^'\\]|\\. match any run of non-quote/non-backslash characters and
    # backslash escape pairs, so escaped quotes (\') and backslashes (\\) —
    # and commas/parens inside titles — do not terminate the capture.
    # Tuples that do not match this shape are simply not extracted
    # (equivalent to the old parser skipping malformed tuples)
    TUPLE_REGEX = /\((\d+),'((?:[^'\\]|\\.)*)','((?:[^'\\]|\\.)*)'\)/

    UNESCAPE_REGEX = /\\(.)/m

    # Resolve MySQL backslash escapes in a captured string literal
    # (same mapping as the old hand-rolled parser)
    def unescape_mysql(str)
      str.gsub(UNESCAPE_REGEX) { UNESCAPES[::Regexp.last_match(1)] || ::Regexp.last_match(1) }
    end
  end
end
