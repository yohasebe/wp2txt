# frozen_string_literal: true

require "sqlite3"
require "json"
require "fileutils"
require "digest"

module Wp2txt
  # SQLite-based cache for global data files (templates, mediawiki aliases, entities)
  # Dramatically speeds up startup by avoiding JSON parsing overhead
  class GlobalDataCache
    CACHE_VERSION = 1
    DEFAULT_CACHE_DIR = File.expand_path("~/.wp2txt/cache")

    # Data categories and their source paths
    # Note: html_entities_combined has no direct source (derived from html_entities + wikipedia_entities)
    DATA_SOURCES = {
      mediawiki: "mediawiki_aliases.json",
      template: "template_aliases.json",
      html_entities: "html_entities.json",
      wikipedia_entities: "wikipedia_entities.json",
      language_metadata: "language_metadata.json",
      language_tiers: "language_tiers.json"
    }.freeze

    # Categories that are derived (combined from multiple sources)
    # These are validated by checking their source files
    DERIVED_SOURCES = {
      html_entities_combined: [:html_entities, :wikipedia_entities]
    }.freeze

    class << self
      attr_accessor :cache_dir, :enabled

      def configure(cache_dir: nil, enabled: true)
        @cache_dir = cache_dir || DEFAULT_CACHE_DIR
        @enabled = enabled
      end

      def cache_path
        @cache_dir ||= DEFAULT_CACHE_DIR
        File.join(@cache_dir, "global_data.sqlite3")
      end

      def data_dir
        File.join(__dir__, "data")
      end

      # Check if cache is valid for all source files
      def cache_valid?
        return false unless @enabled
        return false unless File.exist?(cache_path)

        begin
          db = open_db
          DATA_SOURCES.each do |category, filename|
            source_path = File.join(data_dir, filename)
            next unless File.exist?(source_path)

            meta = load_metadata(db, category)
            return false unless meta

            # Check version
            return false if meta[:cache_version].to_i != CACHE_VERSION

            # Check source file hasn't changed
            source_stat = File.stat(source_path)
            return false if meta[:source_mtime].to_i != source_stat.mtime.to_i
            return false if meta[:source_size].to_i != source_stat.size
          end
          true
        rescue SQLite3::Exception
          false
        ensure
          db&.close
        end
      end

      # Check if a specific category's cache is valid
      def category_valid?(category)
        return false unless @enabled
        return false unless File.exist?(cache_path)

        # For derived categories, check source categories
        if DERIVED_SOURCES.key?(category)
          return DERIVED_SOURCES[category].all? { |src| category_valid?(src) }
        end

        # For unknown categories (not in DATA_SOURCES), just check if it exists in cache
        filename = DATA_SOURCES[category]
        unless filename
          begin
            db = open_db
            row = db.get_first_row("SELECT 1 FROM global_data WHERE category = ?", [category.to_s])
            return !row.nil?
          rescue SQLite3::Exception
            return false
          ensure
            db&.close
          end
        end

        # For known data sources, validate against source file
        begin
          db = open_db
          source_path = File.join(data_dir, filename)
          return true unless File.exist?(source_path)

          meta = load_metadata(db, category)
          return false unless meta
          return false if meta[:cache_version].to_i != CACHE_VERSION

          source_stat = File.stat(source_path)
          return false if meta[:source_mtime].to_i != source_stat.mtime.to_i
          return false if meta[:source_size].to_i != source_stat.size

          true
        rescue SQLite3::Exception
          false
        ensure
          db&.close
        end
      end

      # Load data from cache
      # @param category [Symbol] Data category (:mediawiki, :template, etc.)
      # @return [Hash, nil] Parsed data or nil if not cached or invalid
      def load(category)
        return nil unless @enabled
        return nil unless File.exist?(cache_path)
        return nil unless category_valid?(category)

        begin
          db = open_db
          row = db.get_first_row(
            "SELECT data FROM global_data WHERE category = ?",
            [category.to_s]
          )
          return nil unless row

          JSON.parse(row[0])
        rescue SQLite3::Exception, JSON::ParserError
          nil
        ensure
          db&.close
        end
      end

      # Save data to cache
      # @param category [Symbol] Data category
      # @param data [Hash] Data to cache
      def save(category, data)
        return unless @enabled

        FileUtils.mkdir_p(File.dirname(cache_path))

        begin
          db = open_db
          create_schema(db)

          db.execute(
            "INSERT OR REPLACE INTO global_data (category, data, updated_at) VALUES (?, ?, ?)",
            [category.to_s, JSON.generate(data), Time.now.to_i]
          )

          # For derived categories, save metadata from source files
          if DERIVED_SOURCES.key?(category)
            DERIVED_SOURCES[category].each do |src_category|
              filename = DATA_SOURCES[src_category]
              next unless filename

              source_path = File.join(data_dir, filename)
              next unless File.exist?(source_path)

              source_stat = File.stat(source_path)
              save_metadata(db, src_category,
                source_path: source_path,
                source_mtime: source_stat.mtime.to_i,
                source_size: source_stat.size,
                cache_version: CACHE_VERSION
              )
            end
          else
            # For regular categories, save metadata from the source file
            filename = DATA_SOURCES[category]
            if filename
              source_path = File.join(data_dir, filename)
              if File.exist?(source_path)
                source_stat = File.stat(source_path)
                save_metadata(db, category,
                  source_path: source_path,
                  source_mtime: source_stat.mtime.to_i,
                  source_size: source_stat.size,
                  cache_version: CACHE_VERSION
                )
              end
            end
          end
        rescue SQLite3::Exception => e
          warn "GlobalDataCache: Failed to save #{category}: #{e.message}"
        ensure
          db&.close
        end
      end

      # Load all data categories at once (more efficient)
      # @return [Hash] { category => data }
      def load_all
        return {} unless @enabled
        return {} unless File.exist?(cache_path)

        result = {}
        begin
          db = open_db
          db.execute("SELECT category, data FROM global_data") do |row|
            category = row[0].to_sym
            result[category] = JSON.parse(row[1])
          end
          result
        rescue SQLite3::Exception, JSON::ParserError
          {}
        ensure
          db&.close
        end
      end

      # Save all data categories at once
      # @param data_hash [Hash] { category => data }
      def save_all(data_hash)
        return unless @enabled

        FileUtils.mkdir_p(File.dirname(cache_path))

        begin
          db = open_db
          create_schema(db)

          db.execute("BEGIN TRANSACTION")

          data_hash.each do |category, data|
            db.execute(
              "INSERT OR REPLACE INTO global_data (category, data, updated_at) VALUES (?, ?, ?)",
              [category.to_s, JSON.generate(data), Time.now.to_i]
            )

            # Only save metadata if this is a known data source
            filename = DATA_SOURCES[category]
            if filename
              source_path = File.join(data_dir, filename)
              if File.exist?(source_path)
                source_stat = File.stat(source_path)
                save_metadata(db, category,
                  source_path: source_path,
                  source_mtime: source_stat.mtime.to_i,
                  source_size: source_stat.size,
                  cache_version: CACHE_VERSION
                )
              end
            end
          end

          db.execute("COMMIT")
        rescue SQLite3::Exception => e
          db&.execute("ROLLBACK") rescue nil
          warn "GlobalDataCache: Failed to save all: #{e.message}"
        ensure
          db&.close
        end
      end

      # Clear cache
      def clear!
        FileUtils.rm_f(cache_path)
      end

      # Get cache statistics
      def stats
        return nil unless File.exist?(cache_path)

        begin
          db = open_db
          categories = db.execute("SELECT category, LENGTH(data), updated_at FROM global_data")

          {
            cache_path: cache_path,
            cache_size: File.size(cache_path),
            categories: categories.map do |row|
              {
                category: row[0],
                data_size: row[1],
                updated_at: row[2] ? Time.at(row[2]) : nil
              }
            end
          }
        rescue SQLite3::Exception
          nil
        ensure
          db&.close
        end
      end

      private

      def open_db
        db = SQLite3::Database.new(cache_path)
        db.execute("PRAGMA journal_mode = WAL")
        db.execute("PRAGMA synchronous = NORMAL")
        db
      end

      def create_schema(db)
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS global_data (
            category TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            updated_at INTEGER
          )
        SQL

        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS metadata (
            category TEXT,
            key TEXT,
            value TEXT,
            PRIMARY KEY (category, key)
          )
        SQL
      end

      def save_metadata(db, category, hash)
        hash.each do |key, value|
          db.execute(
            "INSERT OR REPLACE INTO metadata (category, key, value) VALUES (?, ?, ?)",
            [category.to_s, key.to_s, value.to_s]
          )
        end
      end

      def load_metadata(db, category)
        result = {}
        db.execute("SELECT key, value FROM metadata WHERE category = ?", [category.to_s]) do |row|
          result[row[0].to_sym] = row[1]
        end
        result.empty? ? nil : result
      rescue SQLite3::Exception
        nil
      end
    end

    # Initialize with default settings
    configure
  end
end
