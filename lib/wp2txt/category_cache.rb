# frozen_string_literal: true

require "sqlite3"
require "json"
require "fileutils"
require_relative "constants"

module Wp2txt
  # SQLite-based cache for Wikipedia category hierarchy and members
  # Dramatically speeds up repeated category extraction operations
  class CategoryCache
    CACHE_VERSION = 1
    DEFAULT_CACHE_DIR = File.expand_path("~/.wp2txt/cache")

    attr_reader :lang, :cache_path, :expiry_days

    def initialize(lang, cache_dir: nil, expiry_days: nil)
      @lang = lang.to_s
      @cache_dir = cache_dir || DEFAULT_CACHE_DIR
      @expiry_days = expiry_days || DEFAULT_CATEGORY_CACHE_EXPIRY_DAYS
      @cache_path = File.join(@cache_dir, "categories_#{@lang}.sqlite3")
      @db = nil
      ensure_schema
    end

    # Check if a category is cached and fresh
    # @param category_name [String] Category name (without "Category:" prefix)
    # @return [Boolean]
    def cached?(category_name)
      open_db
      row = @db.get_first_row(
        "SELECT cached_at FROM categories WHERE name = ?",
        [normalize_name(category_name)]
      )
      return false unless row

      cached_at = row[0]
      return false unless cached_at

      # Check freshness
      Time.at(cached_at) > Time.now - (@expiry_days * SECONDS_PER_DAY)
    rescue SQLite3::Exception
      false
    end

    # Get category data from cache
    # @param category_name [String] Category name
    # @return [Hash, nil] { pages: [...], subcats: [...] } or nil if not cached
    def get(category_name)
      return nil unless cached?(category_name)

      name = normalize_name(category_name)
      open_db

      pages = []
      subcats = []

      # Get pages
      @db.execute(
        "SELECT page_title FROM category_pages WHERE category_name = ?",
        [name]
      ) do |row|
        pages << row[0]
      end

      # Get subcategories
      @db.execute(
        "SELECT child_name FROM category_hierarchy WHERE parent_name = ?",
        [name]
      ) do |row|
        subcats << row[0]
      end

      { pages: pages, subcats: subcats }
    rescue SQLite3::Exception
      nil
    end

    # Save category data to cache
    # @param category_name [String] Category name
    # @param pages [Array<String>] Article titles in this category
    # @param subcats [Array<String>] Subcategory names
    def save(category_name, pages, subcats)
      name = normalize_name(category_name)
      open_db

      @db.execute("BEGIN TRANSACTION")

      # Update or insert category
      @db.execute(
        "INSERT OR REPLACE INTO categories (name, page_count, subcat_count, cached_at) VALUES (?, ?, ?, ?)",
        [name, pages.size, subcats.size, Time.now.to_i]
      )

      # Clear old pages and hierarchy
      @db.execute("DELETE FROM category_pages WHERE category_name = ?", [name])
      @db.execute("DELETE FROM category_hierarchy WHERE parent_name = ?", [name])

      # Insert pages
      unless pages.empty?
        stmt = @db.prepare("INSERT INTO category_pages (category_name, page_title) VALUES (?, ?)")
        pages.each { |page| stmt.execute([name, page]) }
        stmt.close
      end

      # Insert subcategories
      unless subcats.empty?
        stmt = @db.prepare("INSERT INTO category_hierarchy (parent_name, child_name) VALUES (?, ?)")
        subcats.each { |subcat| stmt.execute([name, normalize_name(subcat)]) }
        stmt.close
      end

      @db.execute("COMMIT")
    rescue SQLite3::Exception => e
      @db&.execute("ROLLBACK") rescue nil
      warn "CategoryCache: Failed to save #{category_name}: #{e.message}"
    end

    # Get all pages in a category tree (recursive)
    # @param category_name [String] Root category name
    # @param max_depth [Integer] Maximum recursion depth (0 = no recursion)
    # @param visited [Set] Already visited categories (for cycle detection)
    # @return [Array<String>] All article titles
    def get_all_pages(category_name, max_depth: 0, visited: nil)
      visited ||= Set.new
      name = normalize_name(category_name)
      return [] if visited.include?(name)

      visited << name
      data = get(name)
      return [] unless data

      pages = data[:pages].dup

      if max_depth > 0
        data[:subcats].each do |subcat|
          pages.concat(get_all_pages(subcat, max_depth: max_depth - 1, visited: visited))
        end
      end

      pages.uniq
    end

    # Get category tree structure
    # @param category_name [String] Root category name
    # @param max_depth [Integer] Maximum recursion depth
    # @return [Hash] Tree structure with category info
    def get_tree(category_name, max_depth: 0)
      build_tree(category_name, max_depth, Set.new)
    end

    # Get statistics for all cached categories
    # @return [Hash] Statistics
    def stats
      open_db

      total_categories = @db.get_first_value("SELECT COUNT(*) FROM categories")
      total_pages = @db.get_first_value("SELECT COUNT(*) FROM category_pages")
      total_relations = @db.get_first_value("SELECT COUNT(*) FROM category_hierarchy")

      oldest_cache = @db.get_first_value("SELECT MIN(cached_at) FROM categories")
      newest_cache = @db.get_first_value("SELECT MAX(cached_at) FROM categories")

      {
        lang: @lang,
        cache_path: @cache_path,
        cache_size: File.exist?(@cache_path) ? File.size(@cache_path) : 0,
        total_categories: total_categories || 0,
        total_pages: total_pages || 0,
        total_relations: total_relations || 0,
        oldest_cache: oldest_cache ? Time.at(oldest_cache) : nil,
        newest_cache: newest_cache ? Time.at(newest_cache) : nil,
        expiry_days: @expiry_days
      }
    rescue SQLite3::Exception
      { lang: @lang, error: "Failed to read stats" }
    end

    # Clear all cached data
    def clear!
      close_db
      FileUtils.rm_f(@cache_path)
      ensure_schema
    end

    # Clear expired entries
    def cleanup_expired!
      open_db
      cutoff = Time.now.to_i - (@expiry_days * SECONDS_PER_DAY)

      @db.execute("BEGIN TRANSACTION")

      # Get expired categories
      expired = []
      @db.execute("SELECT name FROM categories WHERE cached_at < ?", [cutoff]) do |row|
        expired << row[0]
      end

      # Delete expired data
      expired.each do |name|
        @db.execute("DELETE FROM category_pages WHERE category_name = ?", [name])
        @db.execute("DELETE FROM category_hierarchy WHERE parent_name = ?", [name])
        @db.execute("DELETE FROM categories WHERE name = ?", [name])
      end

      @db.execute("COMMIT")

      expired.size
    rescue SQLite3::Exception
      @db&.execute("ROLLBACK") rescue nil
      0
    end

    # Close database connection
    def close
      close_db
    end

    private

    def normalize_name(name)
      name.to_s.sub(/^[Cc]ategory:/, "").strip
    end

    def build_tree(category_name, max_depth, visited)
      name = normalize_name(category_name)
      return nil if visited.include?(name)

      visited << name
      data = get(name)

      result = {
        name: name,
        cached: !data.nil?,
        page_count: data ? data[:pages].size : 0,
        children: []
      }

      if data && max_depth > 0
        data[:subcats].each do |subcat|
          child = build_tree(subcat, max_depth - 1, visited)
          result[:children] << child if child
        end
      end

      result
    end

    def open_db
      return if @db

      FileUtils.mkdir_p(File.dirname(@cache_path))
      @db = SQLite3::Database.new(@cache_path)
      @db.execute("PRAGMA journal_mode = WAL")
      @db.execute("PRAGMA synchronous = NORMAL")
      @db.execute("PRAGMA cache_size = -16000") # 16MB cache
    end

    def close_db
      @db&.close
      @db = nil
    end

    def ensure_schema
      open_db

      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS categories (
          name TEXT PRIMARY KEY,
          page_count INTEGER DEFAULT 0,
          subcat_count INTEGER DEFAULT 0,
          cached_at INTEGER
        )
      SQL

      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS category_pages (
          category_name TEXT NOT NULL,
          page_title TEXT NOT NULL,
          PRIMARY KEY (category_name, page_title)
        )
      SQL

      @db.execute("CREATE INDEX IF NOT EXISTS idx_category_pages_category ON category_pages(category_name)")

      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS category_hierarchy (
          parent_name TEXT NOT NULL,
          child_name TEXT NOT NULL,
          PRIMARY KEY (parent_name, child_name)
        )
      SQL

      @db.execute("CREATE INDEX IF NOT EXISTS idx_hierarchy_parent ON category_hierarchy(parent_name)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_hierarchy_child ON category_hierarchy(child_name)")

      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS metadata (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      SQL

      # Store cache version
      @db.execute(
        "INSERT OR REPLACE INTO metadata (key, value) VALUES ('cache_version', ?)",
        [CACHE_VERSION.to_s]
      )
    rescue SQLite3::Exception => e
      warn "CategoryCache: Failed to create schema: #{e.message}"
    end
  end
end
