# frozen_string_literal: true

require "sqlite3"
require "fileutils"
require "digest"
require "open3"
require "parallel"
require "time"
require "json"
require_relative "regex"
require_relative "section_extractor"

module Wp2txt
  # Local metadata index (Tier 1) built from a multistream dump.
  # Stores per-page categories, section headings, redirects, and the category
  # hierarchy in SQLite, enabling offline exhaustive queries such as
  # "all articles in category X that have a Plot section" without any API access.
  class MetadataIndex
    SCHEMA_VERSION = 1
    CACHE_SUFFIX = "_meta.sqlite3"
    NS_ARTICLE = 0
    NS_CATEGORY = 14

    attr_reader :db_path

    def initialize(db_path)
      @db_path = db_path
      @db = nil
    end

    # Default index location for a given multistream file (mirrors IndexCache naming)
    def self.path_for(multistream_path, cache_dir: nil)
      dir = cache_dir || File.expand_path("~/.wp2txt/cache")
      basename = File.basename(multistream_path, ".*").sub(/\.xml\z/, "")
      path_hash = Digest::MD5.hexdigest(multistream_path)[0, 8]
      File.join(dir, "#{basename}_#{path_hash}#{CACHE_SUFFIX}")
    end

    # Normalize a category name the way MediaWiki treats titles:
    # underscores to spaces, trimmed, first letter capitalized
    def self.normalize_category(name)
      n = name.to_s.tr("_", " ").strip.squeeze(" ")
      return n if n.empty?

      n[0].upcase + n[1..].to_s
    end

    # Remove wiki markup from a heading ('''bold''', [[link|label]], HTML tags)
    def self.clean_heading(text)
      t = text.gsub(/'{2,}/, "")
      t = t.gsub(/\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/) { ::Regexp.last_match(1) }
      t.gsub(/<[^>]+>/, "").strip
    end

    # Expand a section name to its full alias group (bidirectional):
    # "Plot" => ["Plot", "Synopsis", ...]; "Synopsis" => same group
    def self.expand_section_names(name, alias_file: nil)
      aliases = SectionExtractor::DEFAULT_ALIASES
      if alias_file
        custom = SectionExtractor.load_aliases_from_file(alias_file)
        aliases = aliases.merge(custom) unless custom.empty?
      end

      down = name.downcase
      aliases.each do |canonical, list|
        group = [canonical, *list]
        return group if group.any? { |g| g.downcase == down }
      end
      [name]
    end

    # ------------------------------------------------------------------
    # Status
    # ------------------------------------------------------------------

    # True if the index file exists and has a compatible schema
    def built?
      return false unless File.exist?(@db_path)

      meta = read_metadata
      !meta.nil? && meta[:schema_version].to_i == SCHEMA_VERSION && !meta[:built_at].nil?
    rescue SQLite3::Exception
      false
    end

    # True if the index was built from the given (unchanged) multistream file
    def valid_for?(multistream_path)
      return false unless built?
      return false unless File.exist?(multistream_path)

      meta = read_metadata
      stat = File.stat(multistream_path)
      meta[:source_size].to_i == stat.size && meta[:source_mtime].to_i == stat.mtime.to_i
    end

    def stats
      return nil unless File.exist?(@db_path)

      meta = read_metadata || {}
      {
        db_path: @db_path,
        db_size: File.size(@db_path),
        dump_name: meta[:dump_name],
        built_at: meta[:built_at],
        page_count: count_scalar("SELECT COUNT(*) FROM pages"),
        article_count: count_scalar("SELECT COUNT(*) FROM pages WHERE namespace = #{NS_ARTICLE} AND redirect_to IS NULL"),
        category_count: count_scalar("SELECT COUNT(DISTINCT category) FROM page_categories"),
        section_count: count_scalar("SELECT COUNT(*) FROM page_sections")
      }
    end

    def close
      @db&.close
      @db = nil
    end

    # ------------------------------------------------------------------
    # Build API (used by MetadataIndexBuilder)
    # ------------------------------------------------------------------

    def prepare_build!
      FileUtils.mkdir_p(File.dirname(@db_path))
      FileUtils.rm_f(@db_path)
      db = open_db
      db.execute(<<~SQL)
        CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)
      SQL
      db.execute(<<~SQL)
        CREATE TABLE pages (
          page_id INTEGER PRIMARY KEY,
          title TEXT,
          namespace INTEGER,
          redirect_to TEXT,
          text_length INTEGER
        )
      SQL
      db.execute("CREATE TABLE page_categories (page_id INTEGER, category TEXT)")
      db.execute("CREATE TABLE page_sections (page_id INTEGER, heading TEXT, level INTEGER, ord INTEGER)")
      db.execute("CREATE TABLE category_hierarchy (child TEXT, parent TEXT)")
    end

    # Insert one scanned batch: {pages:, categories:, sections:, hierarchy:}
    def insert_batch(rows)
      db = open_db
      db.transaction do
        stmt = db.prepare("INSERT OR IGNORE INTO pages (page_id, title, namespace, redirect_to, text_length) VALUES (?, ?, ?, ?, ?)")
        rows[:pages].each { |r| stmt.execute(r) }
        stmt.close

        stmt = db.prepare("INSERT INTO page_categories (page_id, category) VALUES (?, ?)")
        rows[:categories].each { |r| stmt.execute(r) }
        stmt.close

        stmt = db.prepare("INSERT INTO page_sections (page_id, heading, level, ord) VALUES (?, ?, ?, ?)")
        rows[:sections].each { |r| stmt.execute(r) }
        stmt.close

        stmt = db.prepare("INSERT INTO category_hierarchy (child, parent) VALUES (?, ?)")
        rows[:hierarchy].each { |r| stmt.execute(r) }
        stmt.close
      end
    end

    def finalize_build!(source_path)
      db = open_db
      db.execute("CREATE INDEX IF NOT EXISTS idx_pages_title ON pages(title)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_pc_category ON page_categories(category)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_pc_page ON page_categories(page_id)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_ps_heading ON page_sections(heading COLLATE NOCASE)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_ps_page ON page_sections(page_id)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_ch_parent ON category_hierarchy(parent)")

      stat = File.stat(source_path)
      dump_name = File.basename(source_path)[/\A[a-z0-9_\-]+?-\d{8}/] || File.basename(source_path)
      save_metadata(
        schema_version: SCHEMA_VERSION,
        source_path: source_path,
        source_size: stat.size,
        source_mtime: stat.mtime.to_i,
        dump_name: dump_name,
        built_at: Time.now.utc.iso8601
      )
      db.execute("ANALYZE")
      close
    end

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------

    # Find article titles matching the given filters.
    # @param category [String, nil] category name (without namespace prefix)
    # @param depth [Integer] subcategory recursion depth (0 = exact category only)
    # @param has_section [String, nil] single section heading (alias-aware by default)
    # @param sections [Array<String>, nil] multiple headings (OR match, used as-is)
    # @param alias_set [String, nil] saved alias set name used to expand headings
    # @param use_aliases [Boolean] expand has_section via built-in alias groups
    # @param alias_file [String, nil] custom alias YAML (merged with defaults)
    # @param title_match [String, nil] substring match on title
    # @param limit [Integer] max titles to return (0 = no limit)
    # @param offset [Integer] result offset
    # @return [Array<String>] matching titles ordered by page_id
    def find_articles(category: nil, depth: 0, has_section: nil, sections: nil, alias_set: nil,
                      use_aliases: true, alias_file: nil, title_match: nil, limit: 0, offset: 0)
      cte, where, params = build_article_query(
        category: category, depth: depth, has_section: has_section, sections: sections,
        alias_set: alias_set, use_aliases: use_aliases, alias_file: alias_file, title_match: title_match
      )
      sql = +""
      sql << "WITH RECURSIVE #{cte} " if cte
      sql << "SELECT p.title FROM pages p WHERE #{where} ORDER BY p.page_id"
      sql << " LIMIT #{limit.to_i}" if limit.to_i.positive?
      sql << " OFFSET #{offset.to_i}" if offset.to_i.positive?

      open_db.execute(sql, params).map { |row| row[0] }
    end

    # Count articles matching the same filters as find_articles
    def count_articles(category: nil, depth: 0, has_section: nil, sections: nil, alias_set: nil,
                       use_aliases: true, alias_file: nil, title_match: nil)
      cte, where, params = build_article_query(
        category: category, depth: depth, has_section: has_section, sections: sections,
        alias_set: alias_set, use_aliases: use_aliases, alias_file: alias_file, title_match: title_match
      )
      sql = +""
      sql << "WITH RECURSIVE #{cte} " if cte
      sql << "SELECT COUNT(*) FROM pages p WHERE #{where}"

      open_db.get_first_value(sql, params).to_i
    end

    # Subcategory tree starting at category, as [{name:, depth:}, ...] (BFS order)
    def category_tree(category, depth: 2)
      cat = self.class.normalize_category(category)
      sql = <<~SQL
        WITH RECURSIVE cat_tree(name, d) AS (
          SELECT ?, 0
          UNION
          SELECT ch.child, ct.d + 1
          FROM category_hierarchy ch JOIN cat_tree ct ON ch.parent = ct.name
          WHERE ct.d < #{depth.to_i}
        )
        SELECT name, MIN(d) FROM cat_tree GROUP BY name ORDER BY MIN(d), name
      SQL
      open_db.execute(sql, [cat]).map { |name, d| { name: name, depth: d } }
    end

    # Section heading frequencies across articles, optionally scoped to a category
    def section_stats(category: nil, depth: 0, top_n: 50)
      conds = ["p.namespace = #{NS_ARTICLE}", "p.redirect_to IS NULL"]
      params = []
      cte = nil
      if category
        cte, cond, cat_params = category_condition(category, depth)
        conds << cond
        params.concat(cat_params)
      end
      sql = +""
      sql << "WITH RECURSIVE #{cte} " if cte
      sql << <<~SQL
        SELECT ps.heading, COUNT(*) AS cnt
        FROM page_sections ps JOIN pages p ON p.page_id = ps.page_id
        WHERE #{conds.join(' AND ')}
        GROUP BY ps.heading ORDER BY cnt DESC, ps.heading LIMIT #{top_n.to_i}
      SQL
      open_db.execute(sql, params)
    end

    # Article counts, average positions, and pairwise co-occurrence for a set of
    # headings. Synonymous headings almost never co-occur in the same article,
    # so a high co-occurrence ratio is evidence AGAINST treating them as aliases.
    # @param headings [Array<String>] headings to compare
    # @param category [String, nil] optional category scope
    # @param depth [Integer] category recursion depth
    # @return [Hash] { headings: [{heading:, articles:, avg_position:}],
    #                  pairs: [{a:, b:, both:, cooccurrence_ratio:}] }
    def section_cooccurrence(headings, category: nil, depth: 0)
      scope_cte = nil
      scope_cond = "p.namespace = #{NS_ARTICLE} AND p.redirect_to IS NULL"
      scope_params = []
      if category
        scope_cte, cond, scope_params = category_condition(category, depth)
        scope_cond += " AND #{cond}"
      end

      db = open_db
      with = scope_cte ? "WITH RECURSIVE #{scope_cte} " : ""
      # Placeholders bind positionally: with a recursive CTE the category `?`
      # sits inside the CTE (before any heading `?`); without one it sits
      # inside scope_cond (after the heading `?`)
      cte_params = scope_cte ? scope_params : []
      cond_params = scope_cte ? [] : scope_params

      heading_stats = headings.map do |h|
        row = db.execute(
          "#{with}SELECT COUNT(DISTINCT ps.page_id), AVG(ps.ord) FROM page_sections ps " \
          "JOIN pages p ON p.page_id = ps.page_id " \
          "WHERE ps.heading COLLATE NOCASE = ? AND #{scope_cond}",
          cte_params + [h] + cond_params
        ).first
        { heading: h, articles: row[0].to_i, avg_position: row[1]&.round(2) }
      end

      counts = heading_stats.to_h { |s| [s[:heading], s[:articles]] }
      pairs = headings.combination(2).map do |a, b|
        both = db.get_first_value(
          "#{with}SELECT COUNT(*) FROM (" \
          "SELECT ps.page_id FROM page_sections ps JOIN pages p ON p.page_id = ps.page_id " \
          "WHERE ps.heading COLLATE NOCASE = ? AND #{scope_cond} " \
          "INTERSECT " \
          "SELECT ps.page_id FROM page_sections ps JOIN pages p ON p.page_id = ps.page_id " \
          "WHERE ps.heading COLLATE NOCASE = ? AND #{scope_cond})",
          cte_params + [a] + cond_params + [b] + cond_params
        ).to_i
        min = [counts[a], counts[b]].min
        { a: a, b: b, both: both, cooccurrence_ratio: min.positive? ? (both.to_f / min).round(3) : 0.0 }
      end

      { headings: heading_stats, pairs: pairs }
    end

    # ------------------------------------------------------------------
    # Alias sets (LLM-generated, persisted per dump for reproducibility)
    # ------------------------------------------------------------------

    # Save a named alias set. groups is an array of heading groups, e.g.
    # [["あらすじ", "ストーリー", "物語"], ["脚注", "出典"]]
    def save_alias_set(name, groups)
      raise ArgumentError, "groups must be a non-empty array of arrays" unless groups.is_a?(Array) && !groups.empty? && groups.all? { |g| g.is_a?(Array) && !g.empty? }

      ensure_alias_table
      open_db.execute(
        "INSERT OR REPLACE INTO alias_sets (name, groups, created_at) VALUES (?, ?, ?)",
        [name, JSON.generate(groups), Time.now.utc.iso8601]
      )
      { name: name, groups: groups }
    end

    # @return [Hash, nil] { name:, groups:, created_at: } or nil if not found
    def get_alias_set(name)
      ensure_alias_table
      row = open_db.execute("SELECT name, groups, created_at FROM alias_sets WHERE name = ?", [name]).first
      return nil unless row

      { name: row[0], groups: JSON.parse(row[1]), created_at: row[2] }
    end

    def list_alias_sets
      ensure_alias_table
      open_db.execute("SELECT name, groups, created_at FROM alias_sets ORDER BY name").map do |name, groups, created_at|
        { name: name, group_count: JSON.parse(groups).size, created_at: created_at }
      end
    end

    def delete_alias_set(name)
      ensure_alias_table
      open_db.execute("DELETE FROM alias_sets WHERE name = ?", [name])
      nil
    end

    private

    # Returns [cte_sql_or_nil, where_sql, params]
    def build_article_query(category:, depth:, has_section:, sections: nil, alias_set: nil,
                            use_aliases: true, alias_file: nil, title_match: nil)
      conds = ["p.namespace = #{NS_ARTICLE}", "p.redirect_to IS NULL"]
      params = []
      cte = nil

      if category
        cte, cond, cat_params = category_condition(category, depth)
        conds << cond
        params.concat(cat_params)
      end

      names = resolve_section_names(has_section: has_section, sections: sections,
                                    alias_set: alias_set, use_aliases: use_aliases, alias_file: alias_file)
      if names
        placeholders = names.map { "?" }.join(",")
        conds << "p.page_id IN (SELECT ps.page_id FROM page_sections ps WHERE ps.heading COLLATE NOCASE IN (#{placeholders}))"
        params.concat(names)
      end

      if title_match
        conds << "p.title LIKE ? ESCAPE '\\'"
        params << "%#{escape_like(title_match)}%"
      end

      [cte, conds.join(" AND "), params]
    end

    # Merge has_section / sections into one heading list, expanding through a
    # saved alias set (if given) or the built-in alias groups (single name only).
    def resolve_section_names(has_section:, sections:, alias_set:, use_aliases:, alias_file:)
      names = Array(sections).compact
      names += [has_section] if has_section
      return nil if names.empty?

      if alias_set
        set = get_alias_set(alias_set)
        raise ArgumentError, "alias set not found: #{alias_set}" unless set

        names = names.flat_map { |n| expand_via_groups(n, set[:groups]) }
      elsif use_aliases && names.size == 1 && sections.nil?
        names = self.class.expand_section_names(names.first, alias_file: alias_file)
      end
      names.uniq
    end

    # Bidirectional expansion through an array of heading groups
    def expand_via_groups(name, groups)
      down = name.downcase
      groups.each do |group|
        return group if group.any? { |g| g.downcase == down }
      end
      [name]
    end

    def ensure_alias_table
      open_db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS alias_sets (
          name TEXT PRIMARY KEY,
          groups TEXT,
          created_at TEXT
        )
      SQL
    end

    # Returns [cte_sql_or_nil, condition_sql, params] for a category filter
    def category_condition(category, depth)
      cat = self.class.normalize_category(category)
      if depth.to_i.positive?
        cte = <<~SQL.strip
          cat_tree(name, d) AS (
            SELECT ?, 0
            UNION
            SELECT ch.child, ct.d + 1
            FROM category_hierarchy ch JOIN cat_tree ct ON ch.parent = ct.name
            WHERE ct.d < #{depth.to_i}
          )
        SQL
        cond = "p.page_id IN (SELECT pc.page_id FROM page_categories pc WHERE pc.category IN (SELECT name FROM cat_tree))"
        [cte, cond, [cat]]
      else
        [nil, "p.page_id IN (SELECT pc.page_id FROM page_categories pc WHERE pc.category = ?)", [cat]]
      end
    end

    def escape_like(str)
      str.gsub(/[\\%_]/) { |c| "\\#{c}" }
    end

    def open_db
      return @db if @db

      @db = SQLite3::Database.new(@db_path)
      @db.execute("PRAGMA journal_mode = WAL")
      @db.execute("PRAGMA synchronous = NORMAL")
      @db.execute("PRAGMA cache_size = -64000")
      @db
    end

    def count_scalar(sql)
      open_db.get_first_value(sql).to_i
    rescue SQLite3::Exception
      0
    end

    def read_metadata
      db = open_db
      result = {}
      db.execute("SELECT key, value FROM metadata") do |key, value|
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

  # Builds a MetadataIndex by scanning all streams of a multistream dump in parallel.
  # Workers decompress and regex-scan streams; the parent process owns the sole
  # SQLite connection and inserts each batch from the Parallel `finish` hook.
  class MetadataIndexBuilder
    STREAMS_PER_BATCH = 50

    PAGE_BLOCK_REGEX = %r{<page>(.*?)</page>}m
    TITLE_REGEX = %r{<title>([^<]*)</title>}
    NS_REGEX = %r{<ns>(-?\d+)</ns>}
    ID_REGEX = %r{<id>(\d+)</id>}
    TEXT_REGEX = %r{<text[^>]*>(.*)</text>}m
    HEADING_REGEX = /\A(={2,6})[ \t]*(.+?)[ \t]*={2,6}\z/

    def initialize(multistream_path, stream_offsets, db_path:, num_processes: 4)
      @multistream_path = multistream_path
      @stream_offsets = stream_offsets
      @db_path = db_path
      @num_processes = num_processes
    end

    # Build the index. Yields (batches_done, batches_total) after each batch.
    # @return [MetadataIndex] the built index
    def build(&progress)
      index = MetadataIndex.new(@db_path)
      index.prepare_build!
      # Close before Parallel forks workers so children do not inherit a
      # writable SQLite connection; the finish hook reopens it lazily in
      # the parent, which is the only process that ever writes.
      index.close

      pairs = @stream_offsets.zip(@stream_offsets[1..].to_a + [nil])
      batches = pairs.each_slice(STREAMS_PER_BATCH).to_a
      done = 0

      Parallel.map(
        batches,
        in_processes: @num_processes,
        finish: lambda { |_item, _idx, result|
          index.insert_batch(result)
          done += 1
          progress&.call(done, batches.size)
        }
      ) do |batch|
        self.class.scan_batch(@multistream_path, batch)
      end

      index.finalize_build!(@multistream_path)
      index
    end

    # Scan a batch of [offset, next_offset] stream pairs.
    # Runs inside worker processes: must not touch SQLite.
    def self.scan_batch(multistream_path, offset_pairs)
      out = { pages: [], categories: [], sections: [], hierarchy: [] }
      File.open(multistream_path, "rb") do |f|
        offset_pairs.each do |offset, next_offset|
          f.seek(offset)
          data = next_offset ? f.read(next_offset - offset) : f.read
          xml = decompress_bz2(data)
          xml.scan(PAGE_BLOCK_REGEX) { scan_page(::Regexp.last_match(1), out) }
        end
      end
      out
    end

    def self.decompress_bz2(data)
      stdout, status = Open3.capture2("bzcat", stdin_data: data)
      raise "bzcat failed (exit #{status.exitstatus})" unless status.success?

      stdout.force_encoding(Encoding::UTF_8)
    end

    def self.scan_page(block, out)
      title = block[TITLE_REGEX, 1]
      return unless title && !title.empty?

      page_id = block[ID_REGEX, 1]&.to_i
      return unless page_id

      title = unescape_xml(title)
      ns = (block[NS_REGEX, 1] || "0").to_i
      text = block[TEXT_REGEX, 1] || ""
      text = unescape_xml(text)

      redirect_to = nil
      if (m = REDIRECT_REGEX.match(text))
        redirect_to = m[1].split(/[#|]/).first.to_s.strip
        redirect_to = nil if redirect_to.empty?
      end

      out[:pages] << [page_id, title, ns, redirect_to, text.length]

      categories = text.scan(CATEGORY_REGEX)
                       .map { |c| MetadataIndex.normalize_category(c[0]) }
                       .reject(&:empty?).uniq
      if ns == MetadataIndex::NS_CATEGORY
        child = MetadataIndex.normalize_category(title.sub(/\A[^:]+:/, ""))
        categories.each { |c| out[:hierarchy] << [child, c] } unless child.empty?
      else
        categories.each { |c| out[:categories] << [page_id, c] }
      end

      ord = 0
      text.each_line do |line|
        l = line.chomp
        next unless l.start_with?("==")

        hm = HEADING_REGEX.match(l)
        next unless hm

        heading = MetadataIndex.clean_heading(hm[2])
        next if heading.empty?

        out[:sections] << [page_id, heading, hm[1].length, ord]
        ord += 1
      end
    end

    def self.unescape_xml(str)
      str.gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", '"').gsub("&amp;", "&")
    end
  end
end
