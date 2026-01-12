# frozen_string_literal: true

require "sqlite3"
require "fileutils"
require "digest"

module Wp2txt
  # SQLite-based cache for multistream index
  # Dramatically speeds up repeated index access by storing parsed entries in SQLite
  class IndexCache
    CACHE_VERSION = 1
    CACHE_SUFFIX = ".sqlite3"

    attr_reader :cache_path, :source_path

    def initialize(source_path, cache_dir: nil)
      @source_path = source_path
      @cache_dir = cache_dir || default_cache_dir
      @cache_path = build_cache_path
      @db = nil
    end

    # Check if cache exists and is valid for the current source file
    # @return [Boolean] true if cache is usable
    def valid?
      return false unless File.exist?(@cache_path)
      return false unless File.exist?(@source_path)

      begin
        open_db
        meta = load_metadata
        return false unless meta

        # Check cache version
        return false if meta[:cache_version].to_i != CACHE_VERSION

        # Check source file hasn't changed
        source_stat = File.stat(@source_path)
        return false if meta[:source_mtime].to_i != source_stat.mtime.to_i
        return false if meta[:source_size].to_i != source_stat.size

        true
      rescue SQLite3::Exception
        false
      ensure
        close_db
      end
    end

    # Load index entries from cache
    # @return [Hash] { entries_by_title: {}, entries_by_id: {}, stream_offsets: [] }
    def load
      return nil unless valid?

      entries_by_title = {}
      entries_by_id = {}
      stream_offsets = []

      open_db
      begin
        # Load all entries
        @db.execute("SELECT title, page_id, byte_offset FROM index_entries") do |row|
          title, page_id, offset = row
          entry = { offset: offset, page_id: page_id, title: title }
          entries_by_title[title] = entry
          entries_by_id[page_id] = entry
        end

        # Load stream offsets
        @db.execute("SELECT byte_offset FROM stream_offsets ORDER BY byte_offset") do |row|
          stream_offsets << row[0]
        end

        { entries_by_title: entries_by_title, entries_by_id: entries_by_id, stream_offsets: stream_offsets }
      ensure
        close_db
      end
    end

    # Save index entries to cache
    # @param entries_by_title [Hash] title => entry hash
    # @param stream_offsets [Array<Integer>] sorted stream offsets
    def save(entries_by_title, stream_offsets)
      FileUtils.mkdir_p(File.dirname(@cache_path))

      # Remove old cache if exists
      FileUtils.rm_f(@cache_path)

      open_db
      begin
        create_schema

        # Use transaction for better performance
        @db.execute("BEGIN TRANSACTION")

        # Save metadata
        source_stat = File.stat(@source_path)
        save_metadata(
          source_path: @source_path,
          source_mtime: source_stat.mtime.to_i,
          source_size: source_stat.size,
          cache_version: CACHE_VERSION,
          entry_count: entries_by_title.size
        )

        # Save entries in batches for performance
        stmt = @db.prepare("INSERT INTO index_entries (title, page_id, byte_offset) VALUES (?, ?, ?)")
        entries_by_title.each do |title, entry|
          stmt.execute([title, entry[:page_id], entry[:offset]])
        end
        stmt.close

        # Save stream offsets
        stmt = @db.prepare("INSERT INTO stream_offsets (byte_offset) VALUES (?)")
        stream_offsets.each do |offset|
          stmt.execute([offset])
        end
        stmt.close

        @db.execute("COMMIT")

        true
      rescue SQLite3::Exception => e
        @db.execute("ROLLBACK") rescue nil
        FileUtils.rm_f(@cache_path)
        raise e
      ensure
        close_db
      end
    end

    # Find entries by titles (efficient batch lookup)
    # @param titles [Array<String>] titles to look up
    # @return [Hash] title => entry or nil
    def find_by_titles(titles)
      return {} if titles.empty?
      return {} unless valid?

      results = {}
      open_db
      begin
        # Use IN clause with placeholders for batch lookup
        placeholders = titles.map { "?" }.join(",")
        sql = "SELECT title, page_id, byte_offset FROM index_entries WHERE title IN (#{placeholders})"

        # SQLite3 2.x requires bind variables as an array
        @db.execute(sql, titles) do |row|
          title, page_id, offset = row
          results[title] = { offset: offset, page_id: page_id, title: title }
        end

        results
      ensure
        close_db
      end
    end

    # Get cache statistics
    def stats
      return nil unless File.exist?(@cache_path)

      open_db
      begin
        meta = load_metadata
        entry_count = @db.get_first_value("SELECT COUNT(*) FROM index_entries")
        stream_count = @db.get_first_value("SELECT COUNT(*) FROM stream_offsets")

        {
          cache_path: @cache_path,
          cache_size: File.size(@cache_path),
          entry_count: entry_count,
          stream_count: stream_count,
          source_path: meta[:source_path],
          source_mtime: meta[:source_mtime] ? Time.at(meta[:source_mtime].to_i) : nil,
          cache_version: meta[:cache_version]
        }
      ensure
        close_db
      end
    end

    # Delete cache file
    def clear!
      FileUtils.rm_f(@cache_path)
    end

    private

    def default_cache_dir
      File.expand_path("~/.wp2txt/cache")
    end

    def build_cache_path
      # Use source file basename + hash of full path for uniqueness
      basename = File.basename(@source_path, ".*").sub(/-index$/, "")
      path_hash = Digest::MD5.hexdigest(@source_path)[0, 8]
      File.join(@cache_dir, "#{basename}_#{path_hash}#{CACHE_SUFFIX}")
    end

    def open_db
      @db ||= SQLite3::Database.new(@cache_path)
      # Performance optimizations
      @db.execute("PRAGMA journal_mode = WAL")
      @db.execute("PRAGMA synchronous = NORMAL")
      @db.execute("PRAGMA cache_size = -64000") # 64MB cache
    end

    def close_db
      @db&.close
      @db = nil
    end

    def create_schema
      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS metadata (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      SQL

      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS index_entries (
          title TEXT PRIMARY KEY,
          page_id INTEGER,
          byte_offset INTEGER
        )
      SQL

      @db.execute("CREATE INDEX IF NOT EXISTS idx_page_id ON index_entries(page_id)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_byte_offset ON index_entries(byte_offset)")

      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS stream_offsets (
          byte_offset INTEGER PRIMARY KEY
        )
      SQL
    end

    def save_metadata(hash)
      stmt = @db.prepare("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)")
      hash.each do |key, value|
        stmt.execute([key.to_s, value.to_s])
      end
      stmt.close
    end

    def load_metadata
      result = {}
      @db.execute("SELECT key, value FROM metadata") do |row|
        key, value = row
        result[key.to_sym] = value
      end
      result
    rescue SQLite3::Exception
      nil
    end
  end
end
