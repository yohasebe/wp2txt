# frozen_string_literal: true

require "sqlite3"
require "fileutils"
require "digest"
require "open3"
require "parallel"
require "time"
require_relative "utils"
require_relative "article"
require_relative "metadata_index"

module Wp2txt
  # Tier 2: contentless FTS5 full-text index over cleaned section text.
  # Stores only the inverted index plus a rowid -> (page_id, heading, ord)
  # mapping; the dump itself remains the single source of truth for text
  # (snippets are re-rendered on demand via multistream random access).
  # Queries ATTACH the Tier 1 metadata DB so category/section/redirect
  # filters compose with MATCH in plain SQL.
  class FtsIndex
    SCHEMA_VERSION = 1
    CACHE_SUFFIX = "_fts.sqlite3"

    # Languages without word delimiters: use character-trigram tokenization
    TRIGRAM_LANGS = %w[ja zh ko yue wuu th km lo my bo].freeze
    TOKENIZERS = %w[unicode61 trigram porter].freeze

    attr_reader :db_path, :meta_db_path

    def initialize(db_path, meta_db_path)
      @db_path = db_path
      @meta_db_path = meta_db_path
      @db = nil
    end

    def self.path_for(multistream_path, cache_dir: nil)
      dir = cache_dir || File.expand_path("~/.wp2txt/cache")
      basename = File.basename(multistream_path, ".*").sub(/\.xml\z/, "")
      path_hash = Digest::MD5.hexdigest(multistream_path)[0, 8]
      File.join(dir, "#{basename}_#{path_hash}#{CACHE_SUFFIX}")
    end

    # Pick a tokenizer from the dump's language (e.g. "jawiki-..." -> trigram)
    def self.default_tokenizer(multistream_path)
      lang = File.basename(multistream_path)[/\A([a-z_-]+?)wiki/, 1]
      TRIGRAM_LANGS.include?(lang) ? "trigram" : "unicode61"
    end

    # ------------------------------------------------------------------
    # Status
    # ------------------------------------------------------------------

    def built?
      return false unless File.exist?(@db_path)

      meta = read_metadata
      !meta.nil? && meta[:schema_version].to_i == SCHEMA_VERSION && !meta[:built_at].nil?
    rescue SQLite3::Exception
      false
    end

    def valid_for?(multistream_path)
      return false unless built?
      return false unless File.exist?(multistream_path)

      meta = read_metadata
      stat = File.stat(multistream_path)
      meta[:source_size].to_i == stat.size && meta[:source_mtime].to_i == stat.mtime.to_i
    end

    def tokenizer
      read_metadata&.dig(:tokenizer)
    end

    def stats
      return nil unless File.exist?(@db_path)

      meta = read_metadata || {}
      { db_path: @db_path, db_size: File.size(@db_path),
        tokenizer: meta[:tokenizer], built_at: meta[:built_at],
        section_count: (open_db.get_first_value("SELECT COUNT(*) FROM fts_map") rescue 0) }
    end

    def close
      @db&.close
      @db = nil
    end

    # ------------------------------------------------------------------
    # Build API (parent process only)
    # ------------------------------------------------------------------

    def prepare_build!(tokenizer:)
      raise ArgumentError, "unknown tokenizer: #{tokenizer}" unless TOKENIZERS.include?(tokenizer)

      FileUtils.mkdir_p(File.dirname(@db_path))
      FileUtils.rm_f(@db_path)
      db = open_db
      db.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)")
      db.execute("CREATE VIRTUAL TABLE fts_sections USING fts5(text, content='', tokenize='#{tokenizer}')")
      db.execute("CREATE TABLE fts_map (rowid INTEGER PRIMARY KEY, page_id INTEGER, heading TEXT, ord INTEGER)")
      @pending_tokenizer = tokenizer
      @next_rowid = 0
    end

    # rows: [[page_id, heading, ord, text], ...]
    def insert_batch(rows)
      db = open_db
      db.transaction do
        fts_stmt = db.prepare("INSERT INTO fts_sections (rowid, text) VALUES (?, ?)")
        map_stmt = db.prepare("INSERT INTO fts_map (rowid, page_id, heading, ord) VALUES (?, ?, ?, ?)")
        rows.each do |page_id, heading, ord, text|
          @next_rowid += 1
          fts_stmt.execute([@next_rowid, text])
          map_stmt.execute([@next_rowid, page_id, heading, ord])
        end
        fts_stmt.close
        map_stmt.close
      end
    end

    def finalize_build!(source_path)
      db = open_db
      db.execute("CREATE INDEX IF NOT EXISTS idx_fts_map_page ON fts_map(page_id)")
      db.execute("INSERT INTO fts_sections(fts_sections) VALUES('optimize')")
      stat = File.stat(source_path)
      save_metadata(
        schema_version: SCHEMA_VERSION,
        tokenizer: @pending_tokenizer,
        source_path: source_path,
        source_size: stat.size,
        source_mtime: stat.mtime.to_i,
        built_at: Time.now.utc.iso8601
      )
      close
    end

    # ------------------------------------------------------------------
    # Search
    # ------------------------------------------------------------------

    # @param query [String] search string
    # @param mode [String] "phrase" (literal, default) or "query" (raw FTS5 syntax)
    # @param sections [Array<String>, nil] restrict to these headings
    # @param category [String, nil] category scope (recursion via depth)
    # @param count [String] "capped" (default; stops at count_cap) or "exact"
    # @return [Hash] { total:, total_is_capped:, hits: [{page_id:, title:, heading:, ord:}] }
    def search(query, mode: "phrase", sections: nil, category: nil, depth: 0,
               limit: 20, offset: 0, count: "capped", count_cap: 1000)
      match_expr = mode == "query" ? query : phrase_query(query)

      conds = ["fts_sections MATCH ?", "p.namespace = 0", "p.redirect_to IS NULL"]
      params = [match_expr]
      cte = nil

      if category
        cte, cond, cat_params = category_condition(category, depth)
        conds << cond
        params = cat_params + params if cte     # CTE placeholders precede MATCH in SQL order
        params += cat_params unless cte
      end

      if sections && !sections.empty?
        placeholders = sections.map { "?" }.join(",")
        conds << "fm.heading COLLATE NOCASE IN (#{placeholders})"
        params += sections
      end

      base = "FROM fts_sections f JOIN fts_map fm ON fm.rowid = f.rowid " \
             "JOIN meta.pages p ON p.page_id = fm.page_id WHERE #{conds.join(' AND ')}"
      with = cte ? "WITH RECURSIVE #{cte} " : ""

      db = attached_db
      hits = db.execute(
        "#{with}SELECT fm.page_id, p.title, fm.heading, fm.ord #{base} ORDER BY rank LIMIT ? OFFSET ?",
        params + [limit, offset]
      ).map { |page_id, title, heading, ord| { page_id: page_id, title: title, heading: heading, ord: ord } }

      if count == "exact"
        total = db.get_first_value("#{with}SELECT COUNT(*) #{base}", params).to_i
        { total: total, total_is_capped: false, hits: hits }
      else
        capped = db.get_first_value(
          "#{with}SELECT COUNT(*) FROM (SELECT 1 #{base} LIMIT #{count_cap.to_i + 1})", params
        ).to_i
        { total: [capped, count_cap].min, total_is_capped: capped > count_cap, hits: hits }
      end
    end

    private

    # Escape a literal string as an FTS5 phrase query
    def phrase_query(str)
      %("#{str.gsub('"', '""')}")
    end

    # Category filter against the ATTACHed metadata DB (meta.*); mirrors
    # MetadataIndex#category_condition
    def category_condition(category, depth)
      cat = MetadataIndex.normalize_category(category)
      if depth.to_i.positive?
        cte = <<~SQL.strip
          cat_tree(name, d) AS (
            SELECT ?, 0
            UNION
            SELECT ch.child, ct.d + 1
            FROM meta.category_hierarchy ch JOIN cat_tree ct ON ch.parent = ct.name
            WHERE ct.d < #{depth.to_i}
          )
        SQL
        cond = "p.page_id IN (SELECT pc.page_id FROM meta.page_categories pc WHERE pc.category IN (SELECT name FROM cat_tree))"
        [cte, cond, [cat]]
      else
        [nil, "p.page_id IN (SELECT pc.page_id FROM meta.page_categories pc WHERE pc.category = ?)", [cat]]
      end
    end

    def attached_db
      db = open_db
      unless @attached
        db.execute("ATTACH DATABASE ? AS meta", [@meta_db_path])
        @attached = true
      end
      db
    end

    def open_db
      return @db if @db

      @db = SQLite3::Database.new(@db_path)
      @db.execute("PRAGMA journal_mode = WAL")
      @db.execute("PRAGMA synchronous = NORMAL")
      @db.execute("PRAGMA cache_size = -64000")
      @attached = false
      @db
    end

    def read_metadata
      result = {}
      open_db.execute("SELECT key, value FROM metadata") do |key, value|
        result[key.to_sym] = value
      end
      result
    rescue SQLite3::Exception
      nil
    end

    def save_metadata(hash)
      db = open_db
      stmt = db.prepare("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)")
      hash.each { |k, v| stmt.execute([k.to_s, v.to_s]) }
      stmt.close
    end
  end

  # Renders an article's wikitext into cleaned per-section texts.
  # Shared by the FTS builder (indexing) and Corpus snippets (re-rendering).
  class SectionRenderer
    include Wp2txt

    RENDER_CONFIG = {
      format: :text, title: true, heading: true, list: false, table: false,
      pre: false, ref: false, redirect: false, multiline: false, category: false,
      marker: true, markers: true, extract_citations: false, expand_templates: true
    }.freeze

    # @return [Array<Array(String, Integer, String)>] [heading ("" = lead), ord, text]
    def render_sections(title, wikitext)
      article = Article.new(wikitext, title, false)
      config = RENDER_CONFIG.merge(title: title)

      sections = []
      heading = ""
      ord = 0
      buffer = +""

      flush = lambda do
        text = cleanup(format_wiki(buffer, config)).strip
        sections << [heading, ord, text] unless text.empty?
      end

      article.elements.each do |element|
        if element[0] == :mw_heading
          flush.call
          heading = element[1].to_s.gsub(/\A[\s\n]*=+\s*/, "").gsub(/\s*=+[\s\n]*\z/, "").strip
          ord += 1
          buffer = +""
        else
          buffer << element[1].to_s
        end
      end
      flush.call
      sections
    end
  end

  # Builds an FtsIndex by scanning all streams in parallel: workers decompress,
  # parse, and render cleaned section text; the parent owns the sole SQLite
  # connection and inserts from the Parallel finish hook.
  class FtsIndexBuilder
    # Smaller batches than the metadata builder: rendering dominates, so this
    # keeps progress granular and per-batch IPC payloads moderate
    STREAMS_PER_BATCH = 10

    def initialize(multistream_path, stream_offsets, db_path:, meta_db_path:,
                   tokenizer: nil, num_processes: 4)
      @multistream_path = multistream_path
      @stream_offsets = stream_offsets
      @db_path = db_path
      @meta_db_path = meta_db_path
      @tokenizer = tokenizer || FtsIndex.default_tokenizer(multistream_path)
      @num_processes = num_processes
    end

    def build(&progress)
      index = FtsIndex.new(@db_path, @meta_db_path)
      index.prepare_build!(tokenizer: @tokenizer)
      index.close

      pairs = @stream_offsets.zip(@stream_offsets[1..].to_a + [nil])
      batches = pairs.each_slice(STREAMS_PER_BATCH).to_a
      done = 0

      Parallel.map(
        batches,
        in_processes: @num_processes,
        finish: lambda { |_item, _idx, rows|
          index.insert_batch(rows)
          done += 1
          progress&.call(done, batches.size)
        }
      ) do |batch|
        self.class.scan_batch(@multistream_path, batch)
      end

      index.finalize_build!(@multistream_path)
      index
    end

    # Runs in worker processes: must not touch SQLite
    def self.scan_batch(multistream_path, offset_pairs)
      renderer = SectionRenderer.new
      rows = []
      File.open(multistream_path, "rb") do |f|
        offset_pairs.each do |offset, next_offset|
          f.seek(offset)
          data = next_offset ? f.read(next_offset - offset) : f.read
          xml = MetadataIndexBuilder.decompress_bz2(data)
          xml.scan(MetadataIndexBuilder::PAGE_BLOCK_REGEX) do
            scan_page(::Regexp.last_match(1), renderer, rows)
          end
        end
      end
      rows
    end

    def self.scan_page(block, renderer, rows)
      title = block[MetadataIndexBuilder::TITLE_REGEX, 1]
      return unless title && !title.empty?

      ns = (block[MetadataIndexBuilder::NS_REGEX, 1] || "0").to_i
      return unless ns.zero?

      page_id = block[MetadataIndexBuilder::ID_REGEX, 1]&.to_i
      return unless page_id

      title = MetadataIndexBuilder.unescape_xml(title)
      text = block[MetadataIndexBuilder::TEXT_REGEX, 1] || ""
      text = MetadataIndexBuilder.unescape_xml(text)
      return if REDIRECT_REGEX.match?(text)

      renderer.render_sections(title, text).each do |heading, ord, section_text|
        rows << [page_id, heading, ord, section_text]
      end
    rescue StandardError
      # A single malformed page must not abort the whole batch
      nil
    end
  end
end
