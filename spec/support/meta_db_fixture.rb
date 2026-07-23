# frozen_string_literal: true

require "sqlite3"
require_relative "../../lib/wp2txt/metadata_index"
require_relative "../../lib/wp2txt/fts_index"
require_relative "../../lib/wp2txt/version"

# Synthetic Tier 1 / Tier 2 index DBs for cross-dump (ATTACH) and langlinks
# specs: builds the SQLite files directly, without a real multistream dump
module MetaDbFixture
  # Create a synthetic built metadata DB for LANG in DIR, mimicking what
  # MetadataIndex.path_for + MetadataIndexBuilder produce.
  # @param pages [Array] rows of [page_id, title, namespace, redirect_to, text_length]
  # @param sections [Array] rows of [page_id, heading, level, ord]
  # @return [String] db path
  def create_meta_db(dir, lang:, date:, pages: [], sections: [],
                     built_with: Wp2txt::VERSION, built_at: "2026-01-02T00:00:00Z")
    path = File.join(dir, "#{lang}wiki-#{date}-pages-articles-multistream_deadbeef#{Wp2txt::MetadataIndex::CACHE_SUFFIX}")
    db = SQLite3::Database.new(path)
    db.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)")
    db.execute("CREATE TABLE pages (page_id INTEGER PRIMARY KEY, title TEXT, namespace INTEGER, redirect_to TEXT, text_length INTEGER)")
    db.execute("CREATE TABLE page_categories (page_id INTEGER, category TEXT)")
    db.execute("CREATE TABLE page_sections (page_id INTEGER, heading TEXT, level INTEGER, ord INTEGER)")
    db.execute("CREATE TABLE category_hierarchy (child TEXT, parent TEXT)")
    pages.each { |r| db.execute("INSERT INTO pages VALUES (?, ?, ?, ?, ?)", r) }
    sections.each { |r| db.execute("INSERT INTO page_sections VALUES (?, ?, ?, ?)", r) }
    {
      "schema_version" => Wp2txt::MetadataIndex::SCHEMA_VERSION.to_s,
      "wp2txt_version" => built_with,
      "dump_name" => "#{lang}wiki-#{date}",
      "built_at" => built_at
    }.each { |k, v| db.execute("INSERT INTO metadata VALUES (?, ?)", [k, v]) }
    db.close
    path
  end

  # Create the synthetic FTS DB companion of a meta DB created above
  # (same basename, _fts suffix)
  # @return [String] db path
  def create_fts_db(meta_db_path, built_with: Wp2txt::VERSION, built_at: "2026-01-02T00:00:00Z")
    path = meta_db_path.sub(/#{Wp2txt::MetadataIndex::CACHE_SUFFIX}\z/, Wp2txt::FtsIndex::CACHE_SUFFIX)
    db = SQLite3::Database.new(path)
    db.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)")
    db.execute("CREATE TABLE fts_map (rowid INTEGER PRIMARY KEY, page_id INTEGER, heading TEXT, ord INTEGER)")
    {
      "schema_version" => Wp2txt::FtsIndex::SCHEMA_VERSION.to_s,
      "wp2txt_version" => built_with,
      "built_at" => built_at
    }.each { |k, v| db.execute("INSERT INTO metadata VALUES (?, ?)", [k, v]) }
    db.close
    path
  end
end
