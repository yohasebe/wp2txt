# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "uri"
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
        fulltext: fts.built? ? fts.stats : nil,
        langlinks: @metadata.built? ? @metadata.langlinks_provenance : nil
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

      # Report the exact thresholds used so both the model and the user can see
      # why a group was accepted or rejected, not just that it was
      criteria = { max_cooccurrence_ratio: max_ratio, min_articles: min_articles }
      violations = check_alias_groups(groups, max_ratio: max_ratio, min_articles: min_articles)
      if violations.any? && !force
        return { saved: false, name: name, groups: groups, violations: violations, criteria: criteria,
                 warning: "These heading pairs coexist in the same article more than " \
                          "#{(max_ratio * 100).round}% of the time (both headings appear in at least " \
                          "#{min_articles} articles), so they are likely different sections, not synonyms. " \
                          "Remove them from the group, or pass force: true if you verified them another " \
                          "way (e.g., by reading section contents with get_sections)." }
      end

      @metadata.save_alias_set(name, groups)
      { saved: true, name: name, groups: groups, violations: violations, criteria: criteria }
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

    # Max titles accepted by extract_corpus titles: (larger sets belong in
    # filter-based extraction or a background job)
    TITLES_MAX = 10_000

    # @param output_path [String] JSONL destination (sidecar .meta.json is added)
    # @param content [String] "sections" | "full" | "summary"
    # @param titles [Array<String>, nil] explicit article titles to extract
    #   (e.g. a set determined via query_sql). Normalized, deduplicated, one
    #   redirect hop resolved; missing titles are reported as not_found.
    #   Mutually exclusive with the filter arguments
    # @param chunk_size [Integer, nil] split text into ~N-char chunks (RAG-ready records)
    # @param chunk_overlap [Integer] overlap between consecutive chunks
    # @param max_articles [Integer, nil] sync cap (nil = unlimited, for jobs)
    # @param progress [Proc, nil] called with (titles_done, titles_total) after each batch
    # @param cancel_check [Proc, nil] polled between batches; truthy return aborts with Cancelled
    def extract_corpus(output_path:, content: "sections", sections: nil, alias_set: nil,
                       category: nil, depth: 0, categories: nil, category_match: nil,
                       title_match: nil, limit: 0, titles: nil,
                       chunk_size: nil, chunk_overlap: 0,
                       max_articles: DEFAULT_MAX_SYNC_ARTICLES, num_processes: 4,
                       progress: nil, cancel_check: nil)
      if content == "sections" && Array(sections).empty? && alias_set.nil?
        raise ArgumentError, "content: \"sections\" requires sections or alias_set"
      end
      raise ArgumentError, "chunk_overlap must be smaller than chunk_size" if chunk_size && chunk_overlap >= chunk_size
      raise ArgumentError, "chunking is not supported for content: \"wikitext\"" if chunk_size && content == "wikitext"

      if titles
        raise ArgumentError, "titles must be an array of title strings" unless titles.is_a?(Array)
        if titles.size > TITLES_MAX
          raise ArgumentError, "titles accepts at most #{TITLES_MAX} titles (got #{titles.size}); " \
                               "use filter-based extraction or a background job for larger sets"
        end
        conflicts = []
        conflicts << "category" if category
        conflicts << "categories" if categories
        conflicts << "category_match" if category_match
        conflicts << "title_match" if title_match
        unless conflicts.empty?
          raise ArgumentError, "titles cannot be combined with #{conflicts.join(', ')} — the article " \
                               "set would be defined twice; perform set operations in query_sql and " \
                               "pass the resulting titles via titles:"
        end
      end

      filters = { category: category, depth: depth, categories: categories,
                  category_match: category_match, sections: sections,
                  alias_set: alias_set, title_match: title_match }
      not_found = nil
      titles_record = nil
      if titles
        normalized = titles.map { |t| MetadataIndex.normalize_title(t) }.reject(&:empty?).uniq
        titles_record = { titles_count: normalized.size,
                          titles_sha256: Digest::SHA256.hexdigest(normalized.sort.join("\n")) }
        titles_record[:titles] = normalized if normalized.size <= 100
        total = normalized.size
        resolved, missing = resolve_explicit_titles(normalized)
        not_found = { count: missing.size, sample: missing.first(20) }
        cap = if limit.positive?
                max_articles ? [limit, max_articles].min : limit
              else
                max_articles || resolved.size
              end
        titles = resolved.first(cap)
        # Truncated means "cut by the cap" only; shortfalls from missing
        # titles are explained by not_found, not by this flag
        truncated = resolved.size > titles.size
      else
        total = @metadata.count_articles(**filters)
        cap = if limit.positive?
                max_articles ? [limit, max_articles].min : limit
              else
                max_articles || total
              end
        titles = @metadata.find_articles(**filters, limit: cap)
        truncated = total > titles.size
      end

      resolved_sections = content == "summary" ? [SectionExtractor::SUMMARY_KEY] : expand_with_alias_set(sections, alias_set)
      alias_contents = alias_set ? get_alias_set(alias_set)&.dig(:groups) : nil

      # Close ALL SQLite connections before MultistreamReader forks workers
      # (children must not inherit open database handles)
      close_read_connections

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
        query: (titles_record || filters.compact).merge(
          content: content, resolved_sections: resolved_sections,
          chunk_size: chunk_size, chunk_overlap: chunk_size ? chunk_overlap : nil
        ).compact,
        alias_set_contents: alias_contents,
        total_matching: total,
        articles_extracted: articles_extracted,
        records_written: records_written,
        truncated: truncated,
        not_found: not_found
      ))

      { output_path: output_path, meta_path: meta_path, dump: dump_name,
        total_matching: total, articles_extracted: articles_extracted,
        records_written: records_written, truncated: truncated,
        bytes: File.size(output_path), sample: sample,
        not_found: not_found }.compact
    end

    # Resolve explicit titles against the pages table: existence plus one
    # redirect hop (same rule as get_article). Input order is preserved.
    # @return [Array(Array<String>, Array<String>)] [found_titles, missing_titles]
    def resolve_explicit_titles(titles)
      map = @metadata.redirect_map(titles)
      targets = titles.filter_map { |t| map[t] }
                      .map { |t| MetadataIndex.normalize_title(t) }.uniq
      target_map = targets.empty? ? {} : @metadata.redirect_map(targets)

      found = []
      missing = []
      titles.each do |t|
        if !map.key?(t)
          missing << t
        elsif (target = map[t])
          # Redirect: extract under the resolved title; a redirect whose
          # target does not exist counts as not found
          target = MetadataIndex.normalize_title(target)
          if target_map.key?(target)
            found << target
          else
            missing << t
          end
        else
          found << t
        end
      end
      # Resolution can collapse distinct inputs onto one article (two aliases
      # redirecting to the same target, or a direct title plus its alias):
      # dedupe so no article is extracted twice, preserving first-seen order
      [found.uniq, missing]
    end

    # ------------------------------------------------------------------
    # Read-only SQL (escape hatch for queries the fixed tools cannot express)
    # ------------------------------------------------------------------

    SQL_ROW_LIMIT = 200
    SQL_CELL_LIMIT = 2000
    SQL_TIMEOUT_SECONDS = 30

    # Grace added to the child's own CPU limit: the parent's IO.select deadline
    # should normally fire first; this is the fallback for when it cannot.
    SQL_CHILD_CPU_GRACE = 5

    # Self-imposed deadline for a query child, applied inside the fork.
    #
    # The parent kills the child on timeout, but a child ORPHANED by the
    # parent's death (interrupted test run, closed terminal, crashed server)
    # would otherwise spin forever: sqlite3 holds the GVL inside sqlite3_step,
    # so Ruby's deferred signal handling never reaches a safe point and even
    # SIGTERM is ignored — only SIGKILL or the kernel can stop it. A CPU
    # rlimit is enforced by the kernel regardless of the GVL (SIGXCPU at the
    # soft limit, SIGKILL at the hard one), so the child always dies on its own.
    def self.apply_child_cpu_limit(timeout)
      return unless Process.respond_to?(:setrlimit) && defined?(Process::RLIMIT_CPU)

      seconds = timeout.to_f.ceil
      Process.setrlimit(Process::RLIMIT_CPU,
                        seconds + SQL_CHILD_CPU_GRACE,
                        seconds + (SQL_CHILD_CPU_GRACE * 2))
    rescue StandardError
      # A platform without CPU rlimits keeps the previous behaviour (parent-only kill)
      nil
    end
    SQL_FORBIDDEN = /\b(ATTACH|DETACH|PRAGMA|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|REPLACE|VACUUM|REINDEX)\b/i

    # File-output mode (query_sql output_path:): hard row cap and per-cell
    # clip (insurance against runaway blobs, not context economy)
    SQL_FILE_ROW_LIMIT = 5_000_000
    SQL_FILE_CELL_LIMIT = 64 * 1024

    # Run a read-only SELECT against the metadata DB (with the FTS DB attached
    # as `fts` when built). Defense layers: keyword screening (outside string
    # literals), an SQLITE_OPEN_READONLY connection so writes are impossible at
    # the driver level, and subprocess execution with a hard wall-clock timeout
    # — the sqlite3 gem holds the GVL during C execution, so a runaway query
    # can only be stopped by killing the process running it. On timeout, the
    # error message includes an EXPLAIN QUERY PLAN diagnosis when a likely
    # cause (nested full scans, unbounded recursion) is recognizable.
    #
    # @param attach [Array<String>] language codes of other locally installed
    #   dumps to ATTACH read-only as {lang}_meta / {lang}_fts (e.g. ["en"] →
    #   en_meta.pages). Codes are validated and resolved server-side; user SQL
    #   itself can never contain ATTACH (SQL_FORBIDDEN).
    # @param output_path [String, nil] when given, write ALL rows (up to
    #   SQL_FILE_ROW_LIMIT) to a JSONL file plus a .meta.json sidecar, and
    #   return only a summary + 3-row sample; `limit` is ignored in this mode
    # @param overwrite [Boolean] replace an existing output file (default: refuse)
    def query_sql(sql, limit: SQL_ROW_LIMIT, timeout: SQL_TIMEOUT_SECONDS, attach: [],
                  output_path: nil, overwrite: false)
      raise ArgumentError, "only SELECT/WITH queries are allowed" unless sql =~ /\A\s*(SELECT|WITH)\b/i
      # Screen keywords outside string literals and quoted identifiers only, so
      # legitimate data values (e.g. title LIKE '%Update%') are not rejected
      screened = sql.gsub(/'(?:[^']|'')*'/m, "''").gsub(/"(?:[^"]|"")*"/m, '""')
      raise ArgumentError, "query contains a forbidden keyword" if screened.match?(SQL_FORBIDDEN)

      attachments = resolve_attachments(attach)
      return query_sql_to_file(sql, timeout, attachments, output_path, overwrite) if output_path

      limit = [[limit.to_i, 1].max, 1000].min
      result = if Process.respond_to?(:fork)
                 run_sql_in_subprocess(sql, limit, timeout, attachments)
               elsif attachments.empty?
                 run_sql_on(readonly_db, sql, limit)
               else
                 db = build_readonly_connection(attach_fts: fts.built?, attachments: attachments)
                 begin
                   run_sql_on(db, sql, limit)
                 ensure
                   db.close
                 end
               end
      result[:attached] = attachments_summary(attachments) unless attachments.empty?
      result
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
      close_read_connections
    end

    private

    def close_read_connections
      @metadata.close
      @fts&.close
      @readonly_db&.close
      @readonly_db = nil
    end

    def readonly_db
      @readonly_db ||= build_readonly_connection(attach_fts: fts.built?)
    end

    def build_readonly_connection(attach_fts:, fts_path: fts.db_path, attachments: [])
      db = SQLite3::Database.new(@metadata.db_path, readonly: true)
      db.busy_timeout = 5000
      # Attached databases inherit the main connection's read-only flag
      db.execute("ATTACH DATABASE ? AS fts", [fts_path]) if attach_fts
      # Cross-dump attachments: aliases and paths come only from validated
      # language codes resolved server-side (resolve_attachments), never from
      # user SQL; opened via mode=ro URIs (belt-and-braces with the
      # inherited read-only flag)
      attachments.each do |a|
        db.execute("ATTACH DATABASE ? AS #{a[:alias]}_meta", [readonly_uri(a[:meta_path])])
        db.execute("ATTACH DATABASE ? AS #{a[:alias]}_fts", [readonly_uri(a[:fts_path])]) if a[:fts_path]
      end
      db
    end

    # Language codes accepted by query_sql's attach argument
    ATTACH_LANG_REGEX = /\A[a-z][a-z0-9-]{1,11}\z/

    # Validate attach language codes and resolve them to local index DBs.
    # The argument carries language codes only — never file paths; path
    # resolution (glob the cache dir, inspect dump_name/built state) is
    # server-side. Selection rule: prefer the dump with the same date as the
    # main DB; otherwise take the most recently built one and flag the entry
    # with dump_mismatch so the response must note it.
    def resolve_attachments(attach)
      Array(attach).compact.map(&:to_s).uniq.map do |lang|
        unless lang.match?(ATTACH_LANG_REGEX)
          raise ArgumentError, "invalid language code for attach: #{lang.inspect}"
        end
        if lang == own_lang
          raise ArgumentError, "cannot attach '#{lang}': it is the language of the main database"
        end

        candidates = MetadataIndex.cached_candidates(lang, cache_dir: @cache_dir)
        if candidates.empty?
          raise ArgumentError,
                "no installed index found for '#{lang}' (build it with: wp2txt --build-index -L #{lang})"
        end

        main_date = dump_name[/\d{8}\z/]
        pick = candidates.find { |c| c[:dump_name].to_s.end_with?(main_date.to_s) }
        mismatch = pick.nil?
        pick ||= candidates.first

        fts_path = pick[:db_path].sub(/#{MetadataIndex::CACHE_SUFFIX}\z/, FtsIndex::CACHE_SUFFIX)
        has_fts = File.exist?(fts_path) && fts_db_built?(fts_path)

        { lang: lang, alias: lang.tr("-", "_"),
          meta_path: pick[:db_path], fts_path: has_fts ? fts_path : nil,
          dump_name: pick[:dump_name], built_with: pick[:built_with],
          fts: has_fts, dump_mismatch: mismatch }
      end
    end

    def fts_db_built?(path)
      meta = MetadataIndex.read_metadata_file(path)
      meta && meta[:schema_version].to_i == FtsIndex::SCHEMA_VERSION && !meta[:built_at].nil?
    end

    # "jawiki-20260701" => "ja"
    def own_lang
      dump_name[/\A([a-z0-9_-]+?)wiki/, 1]
    end

    def readonly_uri(path)
      "file:#{URI::DEFAULT_PARSER.escape(File.expand_path(path))}?mode=ro"
    end

    # Row extraction shared by the inline (Windows fallback) and subprocess paths
    def run_sql_on(db, sql, limit)
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
    end

    # Execute the query in a forked child with a hard deadline: the child opens
    # its own read-only connection (no inherited handles), runs the query, and
    # ships the result back over a pipe; a query that outlives the deadline is
    # SIGKILLed — the only reliable abort while the gem holds the GVL.
    def run_sql_in_subprocess(sql, limit, timeout, attachments = [])
      attach_fts = fts.built?
      fts_path = fts.db_path
      reader_io, writer_io = IO.pipe
      pid = Process.fork do
        self.class.apply_child_cpu_limit(timeout)
        reader_io.close
        outcome = begin
          db = build_readonly_connection(attach_fts: attach_fts, fts_path: fts_path, attachments: attachments)
          { ok: run_sql_on(db, sql, limit) }
        rescue SQLite3::Exception => e
          { err: "SQL error: #{e.message}" }
        rescue StandardError => e
          { err: "#{e.class}: #{e.message}" }
        end
        Marshal.dump(outcome, writer_io)
        writer_io.close
        exit!(0)
      end
      writer_io.close

      unless IO.select([reader_io], nil, nil, timeout)
        Process.kill("KILL", pid)
        Process.waitpid(pid)
        raise ArgumentError, "query exceeded the #{timeout}s time limit#{explain_plan_hint(sql)}"
      end
      payload = reader_io.read
      Process.waitpid(pid)
      outcome = Marshal.load(payload)
      raise ArgumentError, outcome[:err] if outcome[:err]

      outcome[:ok]
    ensure
      reader_io&.close
    end

    # ------------------------------------------------------------------
    # query_sql file-output mode (D4 generalized to SQL: the full result
    # goes to disk, the caller receives a summary plus a small sample)
    # ------------------------------------------------------------------

    # Provenance summary of resolved attachments, shared by the interactive
    # and file-output responses
    def attachments_summary(attachments)
      attachments.map do |a|
        entry = { lang: a[:lang], dump_name: a[:dump_name], built_with: a[:built_with], fts: a[:fts] }
        entry[:dump_mismatch] = true if a[:dump_mismatch]
        entry
      end
    end

    # Write the full query result to output_path as JSONL. Atomicity: the
    # child (or inline fallback) writes "#{output_path}.partial"; the parent
    # renames it into place only on success and removes it on every failure
    # path (child crash, timeout kill, error over the pipe) — a partially
    # written file is never presented as a result. The .meta.json sidecar is
    # written by the parent after the rename succeeds.
    def query_sql_to_file(sql, timeout, attachments, output_path, overwrite)
      if File.exist?(output_path) && !overwrite
        raise ArgumentError, "output file already exists: #{output_path} (pass overwrite: true to replace it)"
      end

      partial = "#{output_path}.partial"
      FileUtils.rm_f(partial)
      outcome = begin
        if Process.respond_to?(:fork)
          run_sql_file_in_subprocess(sql, timeout, attachments, partial)
        else
          db = build_readonly_connection(attach_fts: fts.built?, attachments: attachments)
          begin
            run_sql_file_on(db, sql, partial)
          ensure
            db.close
          end
        end
      rescue StandardError
        FileUtils.rm_f(partial)
        raise
      end

      File.rename(partial, output_path)
      write_sql_sidecar(output_path, sql, attachments, outcome)

      result = { output_path: output_path, meta_path: "#{output_path}.meta.json",
                 columns: outcome[:columns], row_count: outcome[:row_count],
                 truncated: outcome[:truncated], cells_clipped: outcome[:cells_clipped],
                 sample: outcome[:sample], bytes: File.size(output_path) }
      result[:attached] = attachments_summary(attachments) unless attachments.empty?
      result
    end

    # Stream the query result into partial_path as JSONL, one object per row
    # keyed by (deduplicated) column names. Runs in the forked child for the
    # subprocess path: the 30s SIGKILL deadline covers the writing too.
    def run_sql_file_on(db, sql, partial_path)
      columns = nil
      row_count = 0
      cells_clipped = 0
      truncated = false
      sample = []

      File.open(partial_path, "w") do |f|
        db.query(sql) do |result|
          columns = unique_columns(result.columns)
          result.each do |row|
            if row_count >= SQL_FILE_ROW_LIMIT
              truncated = true
              break
            end

            record = {}
            row.each_with_index do |value, i|
              if value.is_a?(String) && value.length > SQL_FILE_CELL_LIMIT
                value = "#{value[0, SQL_FILE_CELL_LIMIT]}…"
                cells_clipped += 1
              end
              record[columns[i]] = value
            end
            f.puts(JSON.generate(record))
            sample << record if sample.size < 3
            row_count += 1
          end
        end
      end

      { columns: columns, row_count: row_count, truncated: truncated,
        cells_clipped: cells_clipped, sample: sample }
    end

    # Duplicate result column names (SELECT 1 AS x, 2 AS x) are suffixed
    # (_2, _3, ...) so every JSONL record key is unique
    def unique_columns(columns)
      seen = Hash.new(0)
      columns.map do |c|
        seen[c] += 1
        seen[c] == 1 ? c : "#{c}_#{seen[c]}"
      end
    end

    # Subprocess driver for file-output mode; same fork/pipe/SIGKILL
    # structure as run_sql_in_subprocess, but the child writes the rows to
    # partial_path and ships back only the summary
    def run_sql_file_in_subprocess(sql, timeout, attachments, partial_path)
      attach_fts = fts.built?
      fts_path = fts.db_path
      reader_io, writer_io = IO.pipe
      pid = Process.fork do
        self.class.apply_child_cpu_limit(timeout)
        reader_io.close
        outcome = begin
          db = build_readonly_connection(attach_fts: attach_fts, fts_path: fts_path, attachments: attachments)
          { ok: run_sql_file_on(db, sql, partial_path) }
        rescue SQLite3::Exception => e
          { err: "SQL error: #{e.message}" }
        rescue StandardError => e
          { err: "#{e.class}: #{e.message}" }
        end
        Marshal.dump(outcome, writer_io)
        writer_io.close
        exit!(0)
      end
      writer_io.close

      unless IO.select([reader_io], nil, nil, timeout)
        Process.kill("KILL", pid)
        Process.waitpid(pid)
        raise ArgumentError, "query exceeded the #{timeout}s time limit#{explain_plan_hint(sql)}"
      end
      payload = reader_io.read
      Process.waitpid(pid)
      raise ArgumentError, "query failed: the child process died without a result" if payload.empty?

      outcome = Marshal.load(payload)
      raise ArgumentError, outcome[:err] if outcome[:err]

      outcome[:ok]
    ensure
      reader_io&.close
    end

    # Reproducibility sidecar, written by the parent after the atomic rename
    def write_sql_sidecar(output_path, sql, attachments, outcome)
      File.write("#{output_path}.meta.json", JSON.pretty_generate(
        tool: "query_sql",
        dump: dump_name,
        built_with: @metadata.stats&.dig(:built_with),
        sql: sql,
        attached: attachments.map { |a| { lang: a[:lang], dump_name: a[:dump_name], built_with: a[:built_with] } },
        row_count: outcome[:row_count],
        truncated: outcome[:truncated],
        cells_clipped: outcome[:cells_clipped],
        generated_at: Time.now.utc.iso8601,
        wp2txt_version: Wp2txt::VERSION
      ))
    end

    # Best-effort post-mortem for a timed-out query: EXPLAIN QUERY PLAN is
    # instant and safe (it never executes the query), and the plan tree makes
    # the two common pathologies recognizable
    def explain_plan_hint(sql)
      rows = readonly_db.execute("EXPLAIN QUERY PLAN #{sql}")
      details = rows.map { |r| r[3].to_s }
      by_id = rows.to_h { |r| [r[0], { parent: r[1], detail: r[3].to_s }] }

      nested_scan = rows.any? do |id, parent, _n, detail|
        next false unless detail.to_s.start_with?("SCAN")

        ancestor = parent
        found = false
        while ancestor && (node = by_id[ancestor])
          found ||= node[:detail].start_with?("SCAN")
          ancestor = node[:parent]
        end
        found
      end

      if nested_scan
        " — the query plan shows a full table scan nested inside another full scan " \
        "(likely a cartesian product); join the tables on an indexed key such as page_id"
      elsif details.any? { |d| d.include?("RECURSIVE STEP") }
        " — the query uses a recursive CTE; make sure the recursion is bounded " \
        "(e.g. a depth column with WHERE depth < N)"
      else
        " — narrow the query with additional WHERE filters or aggregate in SQL instead of returning rows"
      end
    rescue StandardError
      ""
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
