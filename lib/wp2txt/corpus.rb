# frozen_string_literal: true

require "json"
require "time"
require_relative "../wp2txt"
require_relative "article"
require_relative "utils"
require_relative "formatter"
require_relative "multistream"
require_relative "metadata_index"
require_relative "fts_index"
require_relative "section_extractor"
require_relative "version"

module Wp2txt
  # Facade over a local dump: single-article access (Tier 0, multistream),
  # exhaustive metadata queries (Tier 1, MetadataIndex), and corpus extraction.
  # Shared by the CLI and the MCP server so both expose identical behavior.
  class Corpus
    include Wp2txt
    include Wp2txt::Formatter

    # Sync extraction cap: larger requests need the (future) job API
    DEFAULT_MAX_SYNC_ARTICLES = 5000

    RENDER_CONFIG = {
      format: :text,
      title: true, heading: true, list: false, table: false, pre: false,
      ref: false, redirect: false, multiline: false,
      category: true, category_only: false, summary_only: false, metadata_only: false,
      marker: true, markers: true, extract_citations: false, expand_templates: true,
      sections: nil, section_output: "structured", min_section_length: 0,
      skip_empty: false, alias_file: nil, no_section_aliases: false,
      show_matched_sections: false
    }.freeze

    # Duck-typed replacement for MultistreamIndex that resolves titles through
    # the IndexCache SQLite file on demand, avoiding loading millions of index
    # entries into memory (important for long-lived server processes).
    class LazyTitleIndex
      def initialize(index_cache)
        @cache = index_cache
      end

      def find_by_title(title)
        @cache.find_by_titles([title])[title]
      end

      def stream_offset_for(title)
        find_by_title(title)&.fetch(:offset, nil)
      end

      def stream_offsets
        @stream_offsets ||= @cache.stream_offsets
      end
    end

    attr_reader :multistream_path, :index_path, :metadata

    def initialize(multistream_path:, index_path:, cache_dir: nil)
      @multistream_path = multistream_path
      @index_path = index_path
      @cache_dir = cache_dir
      @metadata = MetadataIndex.new(MetadataIndex.path_for(multistream_path, cache_dir: cache_dir))
    end

    # Build a Corpus from a language code using the DumpManager cache.
    # Raises with guidance when the dump has not been downloaded yet.
    def self.for_lang(lang, cache_dir: nil)
      manager = DumpManager.new(lang, cache_dir: cache_dir)
      multistream = manager.cached_multistream_path
      index = manager.cached_index_path
      unless File.exist?(multistream) && File.exist?(index)
        raise ArgumentError, "No cached dump for '#{lang}'. Run: wp2txt --build-index -L #{lang}"
      end

      new(multistream_path: multistream, index_path: index, cache_dir: cache_dir)
    end

    def self.for_input(multistream_path, cache_dir: nil)
      candidates = [
        multistream_path.sub(/multistream\.xml\.bz2\z/, "multistream-index.txt.bz2"),
        multistream_path.sub(/\.xml\.bz2\z/, "-index.txt.bz2"),
        multistream_path.sub(/\.xml\.bz2\z/, "-index.txt")
      ].uniq
      index = candidates.find { |c| c != multistream_path && File.exist?(c) }
      raise ArgumentError, "Multistream index file not found next to #{multistream_path}" unless index

      new(multistream_path: multistream_path, index_path: index, cache_dir: cache_dir)
    end

    # ------------------------------------------------------------------
    # Info
    # ------------------------------------------------------------------

    def metadata_built?
      @metadata.built?
    end

    def dump_info
      stats = @metadata.built? ? @metadata.stats : nil
      {
        multistream_path: @multistream_path,
        dump: stats&.dig(:dump_name) || File.basename(@multistream_path),
        tiers: {
          titles: File.exist?(@index_path),
          metadata: @metadata.built?,
          fulltext: fts.built?
        },
        metadata_current: @metadata.built? && @metadata.valid_for?(@multistream_path),
        fulltext_current: fts.built? && fts.valid_for?(@multistream_path),
        stats: stats,
        fulltext: fts.built? ? fts.stats : nil
      }
    end

    def fts
      @fts ||= FtsIndex.new(
        FtsIndex.path_for(@multistream_path, cache_dir: @cache_dir),
        @metadata.db_path
      )
    end

    # ------------------------------------------------------------------
    # Tier 0: single-article access
    # ------------------------------------------------------------------

    # Default cap on article text returned inline (LLM context economy);
    # callers can raise it explicitly, and truncation is always flagged
    DEFAULT_MAX_CHARS = 40_000

    # @param format [String] "text" (cleaned), "wikitext" (raw markup)
    # @param follow_redirect [Boolean] resolve one redirect hop
    # @param max_chars [Integer, nil] truncate text beyond this length (nil = no cap)
    def get_article(title, format: "text", follow_redirect: true, max_chars: DEFAULT_MAX_CHARS)
      page = fetch_page(title, follow_redirect: follow_redirect)
      return nil unless page

      body = case format.to_s
             when "wikitext"
               page[:text]
             else
               render_text(page)
             end
      result = { id: page[:id], title: page[:title], format: format.to_s }
      if max_chars && body.length > max_chars
        result.merge(text: body[0, max_chars], truncated: true, total_chars: body.length)
      else
        result.merge(text: body)
      end
    end

    # Categories of one article, resolved through the same title normalization
    def get_categories(title)
      cats = @metadata.categories_of(title)
      if cats.nil?
        page = fetch_page(title)
        cats = page ? @metadata.categories_of(page[:title]) : nil
      end
      return nil unless cats

      { title: title, categories: cats }
    end

    # Extract specific sections from one article.
    # @param sections [Array<String>] section names ("summary" for lead text)
    # @param alias_set [String, nil] saved alias set used to expand names
    def get_sections(title, sections, alias_set: nil)
      page = fetch_page(title)
      return nil unless page

      resolved = expand_with_alias_set(sections, alias_set)
      config = RENDER_CONFIG.merge(format: :json, sections: resolved, title: page[:title])
      article = Article.new(page[:text], page[:title], false)
      result = format_with_sections(article, config)
      { id: page[:id], title: page[:title], requested: sections, resolved: resolved,
        sections: result ? result["sections"] : {} }
    end

    def list_headings(title)
      page = fetch_page(title)
      return nil unless page

      article = Article.new(page[:text], page[:title], false)
      { id: page[:id], title: page[:title],
        headings: SectionExtractor.new.extract_headings_with_levels(article) }
    end

    # ------------------------------------------------------------------
    # Tier 1: exhaustive queries (delegated to MetadataIndex)
    # ------------------------------------------------------------------

    def find_articles(**filters)
      limit = filters.delete(:limit) || 0
      offset = filters.delete(:offset) || 0
      total = @metadata.count_articles(**filters)
      titles = @metadata.find_articles(**filters, limit: limit, offset: offset)
      { dump: dump_name, total: total, returned: titles.size, titles: titles }
    end

    def category_tree(category, depth: 2)
      { dump: dump_name, tree: @metadata.category_tree(category, depth: depth) }
    end

    def section_stats(category: nil, depth: 0, top_n: 50)
      { dump: dump_name,
        sections: @metadata.section_stats(category: category, depth: depth, top_n: top_n)
                           .map { |h, c| { heading: h, articles: c } } }
    end

    def section_cooccurrence(headings, category: nil, depth: 0)
      @metadata.section_cooccurrence(headings, category: category, depth: depth)
               .merge(dump: dump_name)
    end

    # Guardrail thresholds: pairs whose co-occurrence ratio exceeds
    # GUARDRAIL_MAX_RATIO (with both headings above GUARDRAIL_MIN_ARTICLES)
    # coexist in the same articles and are likely NOT synonyms
    GUARDRAIL_MAX_RATIO = 0.2
    GUARDRAIL_MIN_ARTICLES = 100

    # Save an alias set after mechanically verifying each group: high
    # co-occurrence pairs block the save unless force is set, so protocol
    # compliance does not depend on the calling model's discipline.
    # ------------------------------------------------------------------
    # Tier 2: full-text search
    # ------------------------------------------------------------------

    SNIPPET_CONTEXT = 80

    # Exhaustive full-text search over cleaned section text.
    # @param mode [String] "phrase" (literal, default) or "query" (raw FTS5 syntax)
    # @param count [String] "capped" (fast, default) or "exact" (may take seconds for common terms)
    # @param snippets [Boolean] re-render matched sections from the dump for context
    def search_text(query, mode: "phrase", sections: nil, alias_set: nil,
                    category: nil, depth: 0, limit: 20, offset: 0,
                    count: "capped", snippets: true)
      unless fts.built?
        raise ArgumentError, "Full-text index not built. Run: wp2txt --build-index --fulltext"
      end

      resolved = expand_with_alias_set(sections, alias_set)
      resolved = nil if resolved.empty?
      result = fts.search(query, mode: mode, sections: resolved, category: category,
                          depth: depth, limit: limit, offset: offset, count: count)

      hits = result[:hits]
      attach_snippets(hits, query, mode) if snippets && !hits.empty?

      { dump: dump_name, query: query, mode: mode,
        total: result[:total], total_is_capped: result[:total_is_capped],
        returned: hits.size,
        hits: hits.map do |h|
          { page_id: h[:page_id], title: h[:title],
            section: h[:heading].to_s.empty? ? nil : h[:heading],
            section_path: h[:heading].to_s.empty? ? h[:title] : "#{h[:title]} > #{h[:heading]}",
            snippet: h[:snippet] }.compact
        end }
    end

    def save_alias_set(name, groups, force: false,
                       max_ratio: GUARDRAIL_MAX_RATIO, min_articles: GUARDRAIL_MIN_ARTICLES)
      unless groups.is_a?(Array) && !groups.empty? && groups.all? { |g| g.is_a?(Array) && !g.empty? }
        raise ArgumentError, "groups must be a non-empty array of arrays"
      end

      violations = check_alias_groups(groups, max_ratio: max_ratio, min_articles: min_articles)
      if violations.any? && !force
        return { saved: false, name: name, violations: violations,
                 warning: "These heading pairs frequently coexist in the same articles and are " \
                          "likely NOT synonyms. Remove them from the group, or pass force: true " \
                          "if you have verified them another way (e.g., by reading section contents)." }
      end

      @metadata.save_alias_set(name, groups)
      { saved: true, name: name, groups: groups, violations: violations }
    end

    def get_alias_set(name)
      @metadata.get_alias_set(name)
    end

    def list_alias_sets
      @metadata.list_alias_sets
    end

    # ------------------------------------------------------------------
    # Corpus extraction (synchronous; D4 pattern — results go to disk,
    # the caller receives a summary plus a small sample)
    # ------------------------------------------------------------------

    # Raised via cancel_check to abort a running extraction (job cancellation)
    class Cancelled < StandardError; end

    # Titles fetched/rendered per batch while streaming to disk
    EXTRACT_BATCH_SIZE = 200

    # @param output_path [String] JSONL destination (sidecar .meta.json is added)
    # @param content [String] "sections" | "full" | "summary"
    # @param chunk_size [Integer, nil] split text into ~N-char chunks (RAG-ready records)
    # @param chunk_overlap [Integer] overlap between consecutive chunks
    # @param max_articles [Integer, nil] sync cap (nil = unlimited, for jobs)
    # @param progress [Proc, nil] called with (titles_done, titles_total) after each batch
    # @param cancel_check [Proc, nil] polled between batches; truthy return aborts with Cancelled
    def extract_corpus(output_path:, content: "sections", sections: nil, alias_set: nil,
                       category: nil, depth: 0, categories: nil, category_match: nil,
                       title_match: nil, limit: 0,
                       chunk_size: nil, chunk_overlap: 0,
                       max_articles: DEFAULT_MAX_SYNC_ARTICLES, num_processes: 4,
                       progress: nil, cancel_check: nil)
      if content == "sections" && Array(sections).empty? && alias_set.nil?
        raise ArgumentError, "content: \"sections\" requires sections or alias_set"
      end
      raise ArgumentError, "chunk_overlap must be smaller than chunk_size" if chunk_size && chunk_overlap >= chunk_size
      raise ArgumentError, "chunking is not supported for content: \"wikitext\"" if chunk_size && content == "wikitext"

      filters = { category: category, depth: depth, categories: categories,
                  category_match: category_match, sections: sections,
                  alias_set: alias_set, title_match: title_match }
      total = @metadata.count_articles(**filters)
      cap = if limit.positive?
              max_articles ? [limit, max_articles].min : limit
            else
              max_articles || total
            end
      titles = @metadata.find_articles(**filters, limit: cap)
      truncated = total > titles.size

      resolved_sections = content == "summary" ? [SectionExtractor::SUMMARY_KEY] : expand_with_alias_set(sections, alias_set)
      alias_contents = alias_set ? get_alias_set(alias_set)&.dig(:groups) : nil

      # Close read connections before MultistreamReader forks workers
      @metadata.close

      articles_extracted = 0
      records_written = 0
      titles_done = 0
      sample = []

      File.open(output_path, "w") do |f|
        titles.each_slice(EXTRACT_BATCH_SIZE) do |batch|
          raise Cancelled if cancel_check&.call

          pages = reader.extract_articles_parallel(batch, num_processes: num_processes)
          batch.each do |t|
            page = pages[t]
            next unless page

            records = build_records(page, content, resolved_sections, chunk_size, chunk_overlap)
            next if records.empty?

            articles_extracted += 1
            records.each do |record|
              f.puts(JSON.generate(record))
              records_written += 1
              sample << record if sample.size < 3
            end
          end
          titles_done += batch.size
          progress&.call(titles_done, titles.size)
        end
      end

      meta_path = "#{output_path}.meta.json"
      File.write(meta_path, JSON.pretty_generate(
        tool: "wp2txt #{Wp2txt::VERSION}",
        dump: dump_name,
        generated_at: Time.now.utc.iso8601,
        query: filters.compact.merge(content: content, resolved_sections: resolved_sections,
                                     chunk_size: chunk_size, chunk_overlap: chunk_size ? chunk_overlap : nil).compact,
        alias_set_contents: alias_contents,
        total_matching: total,
        articles_extracted: articles_extracted,
        records_written: records_written,
        truncated: truncated
      ))

      { output_path: output_path, meta_path: meta_path, dump: dump_name,
        total_matching: total, articles_extracted: articles_extracted,
        records_written: records_written, truncated: truncated,
        bytes: File.size(output_path), sample: sample }
    end

    # ------------------------------------------------------------------
    # Read-only SQL (escape hatch for queries the fixed tools cannot express)
    # ------------------------------------------------------------------

    SQL_ROW_LIMIT = 200
    SQL_CELL_LIMIT = 2000
    SQL_FORBIDDEN = /\b(ATTACH|DETACH|PRAGMA|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|REPLACE|VACUUM|REINDEX)\b/i

    # Run a read-only SELECT against the metadata DB (with the FTS DB attached
    # as `fts` when built). Double-layered: keyword screening plus an
    # SQLITE_OPEN_READONLY connection, so writes are impossible at the driver
    # level even if the screen were bypassed.
    #
    # NOTE: there is no execution-time cap. The sqlite3 gem holds the GVL during
    # a query's C execution, so no in-process watchdog (thread interrupt or
    # Timeout) can abort a pathological query (e.g. an unfiltered join over tens
    # of millions of rows); it would hang this request until the process is
    # restarted. Callers must filter/aggregate. A subprocess-isolated hard
    # timeout is tracked as a follow-up.
    def query_sql(sql, limit: SQL_ROW_LIMIT)
      raise ArgumentError, "only SELECT/WITH queries are allowed" unless sql =~ /\A\s*(SELECT|WITH)\b/i
      raise ArgumentError, "query contains a forbidden keyword" if sql.match?(SQL_FORBIDDEN)

      limit = [[limit.to_i, 1].max, 1000].min
      db = readonly_db
      columns = nil
      rows = []
      db.query(sql) do |result|
        columns = result.columns
        result.each do |row|
          break if rows.size >= limit

          rows << row.map { |v| v.is_a?(String) && v.length > SQL_CELL_LIMIT ? "#{v[0, SQL_CELL_LIMIT]}…" : v }
        end
      end
      { columns: columns, rows: rows, row_count: rows.size, truncated: rows.size >= limit }
    rescue SQLite3::Exception => e
      raise ArgumentError, "SQL error: #{e.message}"
    end

    # CREATE statements of all tables available to query_sql
    def describe_schema
      db = readonly_db
      schemas = { meta: db.execute("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL").map(&:first) }
      if fts.built?
        schemas[:fts] = db.execute("SELECT sql FROM fts.sqlite_master WHERE sql IS NOT NULL").map(&:first)
      end
      schemas
    end

    def close
      @metadata.close
      @fts&.close
      @readonly_db&.close
      @readonly_db = nil
    end

    private

    def readonly_db
      @readonly_db ||= begin
        db = SQLite3::Database.new(@metadata.db_path, readonly: true)
        db.busy_timeout = 5000
        # Attached databases inherit the main connection's read-only flag
        db.execute("ATTACH DATABASE ? AS fts", [fts.db_path]) if fts.built?
        db
      end
    end

    # Re-render the matched section of each hit from the dump and cut a window
    # around the first occurrence of the search term (contentless FTS stores no
    # text, so the dump is the source of truth for snippets)
    def attach_snippets(hits, query, mode)
      needle = mode == "query" ? query[/"([^"]+)"/, 1] || query[/\w{3,}/] || query : query
      renderer = SectionRenderer.new
      pages = {}
      hits.each do |hit|
        page = pages[hit[:page_id]] ||= reader.extract_article(hit[:title])
        next unless page

        section = renderer.render_sections(page[:title], page[:text])
                          .find { |_h, ord, _t| ord == hit[:ord] }
        next unless section

        text = section[2]
        pos = needle ? text.downcase.index(needle.downcase) : nil
        hit[:snippet] = if pos
                          from = [pos - SNIPPET_CONTEXT, 0].max
                          "#{'…' if from.positive?}#{text[from, needle.length + SNIPPET_CONTEXT * 2]}…"
                        else
                          "#{text[0, SNIPPET_CONTEXT * 2]}…"
                        end
      end
    end

    def dump_name
      @dump_name ||= @metadata.built? ? @metadata.stats[:dump_name] : File.basename(@multistream_path)
    end

    def reader
      @reader ||= begin
        cache = IndexCache.new(@index_path, cache_dir: @cache_dir)
        index = if cache.valid?
                  LazyTitleIndex.new(cache)
                else
                  MultistreamIndex.new(@index_path, use_cache: true, cache_dir: @cache_dir, show_progress: false)
                end
        # Memoize stream offsets in the parent before any Parallel fork, so
        # workers inherit the array instead of racing on the SQLite cache
        index.stream_offsets
        MultistreamReader.new(@multistream_path, index)
      end
    end

    # Resolve a title the way MediaWiki does: try the exact form, then
    # normalized variants (underscores to spaces, first letter capitalized).
    # Cold-start LLM clients routinely send un-normalized titles.
    def fetch_page(title, follow_redirect: true)
      page = nil
      title_variants(title).each do |t|
        page = reader.extract_article(t)
        break if page
      end
      return nil unless page

      if follow_redirect && (m = REDIRECT_REGEX.match(page[:text].to_s))
        target = m[1].split(/[#|]/).first.to_s.strip
        redirected = target.empty? ? nil : reader.extract_article(target)
        page = redirected if redirected
      end
      page
    end

    def title_variants(title)
      variants = [title]
      normalized = title.tr("_", " ").squeeze(" ").strip
      variants << normalized
      variants << (normalized[0].to_s.upcase + normalized[1..].to_s) unless normalized.empty?
      variants.uniq
    end

    def render_text(page)
      config = RENDER_CONFIG.merge(format: :text, title: page[:title])
      article = Article.new(page[:text], page[:title], false)
      format_article(article, config).to_s
    end

    # Run the co-occurrence check over every pair in every group; returns pairs
    # that look like distinct section roles rather than synonyms
    def check_alias_groups(groups, max_ratio:, min_articles:)
      violations = []
      groups.each do |group|
        next if group.size < 2

        result = @metadata.section_cooccurrence(group)
        counts = result[:headings].to_h { |h| [h[:heading], h[:articles]] }
        result[:pairs].each do |pair|
          next if [counts[pair[:a]], counts[pair[:b]]].min < min_articles
          violations << pair if pair[:cooccurrence_ratio] > max_ratio
        end
      end
      violations
    end

    def expand_with_alias_set(sections, alias_set)
      names = Array(sections).compact
      return names unless alias_set

      set = @metadata.get_alias_set(alias_set)
      raise ArgumentError, "alias set not found: #{alias_set}" unless set

      base = names.empty? ? set[:groups].map(&:first) : names
      base.flat_map do |n|
        group = set[:groups].find { |g| g.any? { |x| x.downcase == n.downcase } }
        group || [n]
      end.uniq
    end

    # Build the JSONL records for one page. Without chunking this is one record
    # per article; with chunking, one RAG-ready record per (section, chunk).
    def build_records(page, content, resolved_sections, chunk_size, chunk_overlap)
      article = Article.new(page[:text], page[:title], false)
      categories = article.categories.flatten

      if content == "wikitext"
        # Raw markup for structure mining (infoboxes, templates, citations)
        [{ id: page[:id], title: page[:title], wikitext: page[:text], categories: categories }]
      elsif content == "full"
        config = RENDER_CONFIG.merge(format: :text, title: page[:title], category: false)
        text = format_article(article, config).to_s.strip
        return [] if text.empty?
        return chunk_records(page, nil, text, categories, chunk_size, chunk_overlap) if chunk_size

        [{ id: page[:id], title: page[:title], text: text, categories: categories }]
      else # "sections" / "summary"
        config = RENDER_CONFIG.merge(format: :json, sections: resolved_sections, title: page[:title])
        result = format_with_sections(article, config)
        return [] unless result

        present = (result["sections"] || {}).reject { |_k, v| v.nil? || v.empty? }
        return [] if present.empty?

        if chunk_size
          return present.flat_map do |section, text|
            chunk_records(page, section, text, categories, chunk_size, chunk_overlap)
          end
        end

        [{ id: page[:id], title: page[:title], sections: present,
           section_path: present.keys.map { |k| "#{page[:title]} > #{k}" },
           categories: categories }]
      end
    end

    def chunk_records(page, section, text, categories, chunk_size, chunk_overlap)
      chunks = chunk_text(text, chunk_size, chunk_overlap)
      path = section ? "#{page[:title]} > #{section}" : page[:title]
      chunks.each_with_index.map do |chunk, i|
        { id: page[:id], title: page[:title], section: section, section_path: path,
          chunk_index: i, chunk_count: chunks.size, text: chunk, categories: categories }
      end
    end

    # Character-based chunking that prefers to break at a paragraph or sentence
    # boundary within the last quarter of the window
    def chunk_text(text, size, overlap)
      return [text] if text.length <= size

      chunks = []
      start = 0
      while start < text.length
        window_end = [start + size, text.length].min
        if window_end < text.length
          slice = text[start...window_end]
          boundary = slice.rindex(/[\n。.!?！？]/)
          window_end = start + boundary + 1 if boundary && boundary >= size * 3 / 4
        end
        chunks << text[start...window_end]
        break if window_end >= text.length

        start = [window_end - overlap, start + 1].max
      end
      chunks
    end
  end
end
