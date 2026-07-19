# frozen_string_literal: true

require "json"
require "time"
require_relative "../wp2txt"
require_relative "article"
require_relative "utils"
require_relative "formatter"
require_relative "multistream"
require_relative "metadata_index"
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
          metadata: @metadata.built?
        },
        metadata_current: @metadata.built? && @metadata.valid_for?(@multistream_path),
        stats: stats
      }
    end

    # ------------------------------------------------------------------
    # Tier 0: single-article access
    # ------------------------------------------------------------------

    # @param format [String] "text" (cleaned), "wikitext" (raw markup)
    # @param follow_redirect [Boolean] resolve one redirect hop
    def get_article(title, format: "text", follow_redirect: true)
      page = fetch_page(title, follow_redirect: follow_redirect)
      return nil unless page

      body = case format.to_s
             when "wikitext"
               page[:text]
             else
               render_text(page)
             end
      { id: page[:id], title: page[:title], format: format.to_s, text: body }
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

    def save_alias_set(name, groups)
      @metadata.save_alias_set(name, groups)
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

    # @param output_path [String] JSONL destination (sidecar .meta.json is added)
    # @param content [String] "sections" | "full" | "summary"
    # @param max_articles [Integer] sync cap; larger matches are truncated (flagged)
    def extract_corpus(output_path:, content: "sections", sections: nil, alias_set: nil,
                       category: nil, depth: 0, title_match: nil, limit: 0,
                       max_articles: DEFAULT_MAX_SYNC_ARTICLES, num_processes: 4)
      if content == "sections" && Array(sections).empty? && alias_set.nil?
        raise ArgumentError, "content: \"sections\" requires sections or alias_set"
      end

      filters = { category: category, depth: depth, sections: sections,
                  alias_set: alias_set, title_match: title_match }
      total = @metadata.count_articles(**filters)
      cap = limit.positive? ? [limit, max_articles].min : max_articles
      titles = @metadata.find_articles(**filters, limit: cap)
      truncated = total > titles.size

      resolved_sections = content == "summary" ? [SectionExtractor::SUMMARY_KEY] : expand_with_alias_set(sections, alias_set)

      # Close read connections before MultistreamReader forks workers
      @metadata.close
      pages = reader.extract_articles_parallel(titles, num_processes: num_processes)

      records = []
      titles.each do |t|
        page = pages[t]
        next unless page

        record = build_record(page, content, resolved_sections)
        records << record if record
      end

      File.open(output_path, "w") do |f|
        records.each { |r| f.puts(JSON.generate(r)) }
      end
      meta_path = "#{output_path}.meta.json"
      File.write(meta_path, JSON.pretty_generate(
        tool: "wp2txt #{Wp2txt::VERSION}",
        dump: dump_name,
        generated_at: Time.now.utc.iso8601,
        query: filters.compact.merge(content: content, resolved_sections: resolved_sections).compact,
        alias_set_contents: alias_set ? get_alias_set(alias_set)&.dig(:groups) : nil,
        total_matching: total,
        extracted: records.size,
        truncated: truncated
      ))

      { output_path: output_path, meta_path: meta_path, dump: dump_name,
        total_matching: total, extracted: records.size, truncated: truncated,
        bytes: File.size(output_path), sample: records.first(3) }
    end

    def close
      @metadata.close
    end

    private

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
        MultistreamReader.new(@multistream_path, index)
      end
    end

    def fetch_page(title, follow_redirect: true)
      page = reader.extract_article(title)
      return nil unless page

      if follow_redirect && (m = REDIRECT_REGEX.match(page[:text].to_s))
        target = m[1].split(/[#|]/).first.to_s.strip
        redirected = target.empty? ? nil : reader.extract_article(target)
        page = redirected if redirected
      end
      page
    end

    def render_text(page)
      config = RENDER_CONFIG.merge(format: :text, title: page[:title])
      article = Article.new(page[:text], page[:title], false)
      format_article(article, config).to_s
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

    def build_record(page, content, resolved_sections)
      article = Article.new(page[:text], page[:title], false)
      categories = article.categories.flatten

      case content
      when "full"
        config = RENDER_CONFIG.merge(format: :text, title: page[:title], category: false)
        { id: page[:id], title: page[:title], text: format_article(article, config).to_s.strip,
          categories: categories }
      else # "sections" / "summary"
        config = RENDER_CONFIG.merge(format: :json, sections: resolved_sections, title: page[:title])
        result = format_with_sections(article, config)
        return nil unless result

        present = (result["sections"] || {}).reject { |_k, v| v.nil? || v.empty? }
        return nil if present.empty?

        { id: page[:id], title: page[:title], sections: present,
          section_path: present.keys.map { |k| "#{page[:title]} > #{k}" },
          categories: categories }
      end
    end
  end
end
