# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "multistream"

module Wp2txt
  # Manages test data extraction and caching from Wikipedia dumps
  class TestDataManager
    CACHE_DIR = "tmp/test_cache"
    CACHE_EXPIRY_DAYS = 30

    # Supported test languages
    TEST_LANGUAGES = [:en, :zh, :ja, :ru, :ar, :ko].freeze

    # Test levels with article counts
    TEST_LEVELS = {
      unit: 500,
      integration: 5000,
      validation: :all
    }.freeze

    attr_reader :lang, :level, :cache_dir

    def initialize(lang, level: :unit, cache_dir: CACHE_DIR)
      @lang = lang.to_sym
      @level = level.to_sym
      @cache_dir = cache_dir
      @dump_manager = DumpManager.new(@lang, cache_dir: File.join(@cache_dir, "dumps"))

      validate_inputs!
      FileUtils.mkdir_p(@cache_dir)
    end

    # Get test articles, downloading/extracting if needed
    def articles
      ensure_cache_fresh
      load_cached_articles
    end

    # Force refresh of cached data
    def refresh!
      FileUtils.rm_f(cache_path)
      articles
    end

    # Check if cache exists and is fresh
    def cache_fresh?
      return false unless File.exist?(cache_path)

      File.mtime(cache_path) > Time.now - (CACHE_EXPIRY_DAYS * 86400)
    end

    # Path to cached articles JSON
    def cache_path
      article_count = TEST_LEVELS[@level]
      count_str = article_count == :all ? "all" : article_count.to_s
      File.join(@cache_dir, @lang.to_s, "#{@level}_#{count_str}_#{dump_date}.json")
    end

    # Get dump date being used
    def dump_date
      @dump_manager.latest_dump_date
    end

    # Get summary of available test data
    def self.status
      status = {}
      TEST_LANGUAGES.each do |lang|
        status[lang] = {}
        TEST_LEVELS.keys.each do |level|
          next if level == :validation  # Skip validation level for status

          manager = new(lang, level: level)
          status[lang][level] = {
            cached: File.exist?(manager.cache_path),
            fresh: manager.cache_fresh?,
            path: manager.cache_path
          }
        end
      end
      status
    end

    private

    def validate_inputs!
      raise ArgumentError, "Unknown language: #{@lang}" unless TEST_LANGUAGES.include?(@lang)
      raise ArgumentError, "Unknown level: #{@level}" unless TEST_LEVELS.key?(@level)
    end

    def ensure_cache_fresh
      return if cache_fresh?

      puts "Cache stale or missing for #{@lang}/#{@level}, extracting..."
      extract_and_cache_articles
    end

    def load_cached_articles
      return [] unless File.exist?(cache_path)

      JSON.parse(File.read(cache_path), symbolize_names: true)
    end

    def extract_and_cache_articles
      # Download index if needed
      index_path = @dump_manager.download_index
      multistream_path = @dump_manager.download_multistream

      # Create multistream reader
      reader = MultistreamReader.new(multistream_path, index_path)

      # Determine how many articles to extract
      count = TEST_LEVELS[@level]
      count = reader.index.size if count == :all

      # Extract articles
      puts "Extracting #{count} articles for #{@lang}/#{@level}..."
      articles = extract_articles_from_streams(reader, count)

      # Save to cache
      save_to_cache(articles)

      articles
    end

    def extract_articles_from_streams(reader, count)
      articles = []
      streams_needed = estimate_streams_needed(reader, count)

      reader.each_article_in_first_streams(streams_needed) do |page|
        articles << {
          title: page[:title],
          id: page[:id],
          text: page[:text]
        }

        if articles.size % 100 == 0
          print "\r  Extracted: #{articles.size} / #{count}"
        end

        break if articles.size >= count
      end

      puts "\r  Extracted: #{articles.size} articles"
      articles.first(count)
    end

    def estimate_streams_needed(reader, count)
      # Estimate based on index data
      total_articles = reader.index.size
      total_streams = reader.index.stream_offsets.size

      return 1 if total_streams == 0

      articles_per_stream = total_articles.to_f / total_streams
      streams = (count / articles_per_stream).ceil

      # Add buffer
      [(streams * 1.2).ceil, total_streams].min
    end

    def save_to_cache(articles)
      FileUtils.mkdir_p(File.dirname(cache_path))

      File.open(cache_path, "w") do |f|
        f.write(JSON.pretty_generate(articles))
      end

      puts "  Cached to: #{cache_path}"
    end
  end

  # Issue detector for validation
  class IssueDetector
    ISSUE_TYPES = {
      # Markup remnants
      wiki_links: /\[\[|\]\]/,
      templates: /\{\{|\}\}/,
      html_tags: /<(?!br|hr)[a-z]+[^>]*>/i,
      ref_tags: /<ref|<\/ref>/i,
      table_markup: /\{\||\|\}/,

      # Output quality
      excessive_newlines: /\n{4,}/,
      empty_parens: /\(\s*\)|（\s*）/,
      pipe_remnants: /\|{2,}|\|\s*$/,
      empty_brackets: /\[\s*\]|【\s*】/,

      # Encoding issues
      replacement_char: /\uFFFD/,
      null_bytes: /\x00/,

      # Suspicious patterns
      magic_words: /__[A-Z]+__/,
      html_entities: /&[a-z]+;|&#\d+;/i
    }.freeze

    attr_reader :issues

    def initialize
      @issues = []
    end

    # Analyze an article for issues
    def analyze(title:, input:, output:, processing_time: nil)
      article_issues = []

      # Check for markup remnants in output
      ISSUE_TYPES.each do |issue_type, pattern|
        matches = output.scan(pattern)
        next if matches.empty?

        matches.uniq.first(3).each do |match|
          context = extract_context(output, match)
          article_issues << {
            type: issue_type,
            match: match,
            context: context
          }
        end
      end

      # Check for processing issues
      if output.strip.empty? && !redirect?(input)
        article_issues << {
          type: :empty_output,
          match: nil,
          context: input[0..200]
        }
      end

      # Check compression ratio (output should be smaller but not too much)
      if input.length > 1000
        ratio = output.length.to_f / input.length
        if ratio < 0.05
          article_issues << {
            type: :excessive_compression,
            match: "#{(ratio * 100).round(1)}%",
            context: "Input: #{input.length} chars, Output: #{output.length} chars"
          }
        end
      end

      # Check processing time
      if processing_time && processing_time > 5.0
        article_issues << {
          type: :slow_processing,
          match: "#{processing_time.round(2)}s",
          context: "Article length: #{input.length} chars"
        }
      end

      return if article_issues.empty?

      @issues << {
        title: title,
        timestamp: Time.now.iso8601,
        issue_count: article_issues.size,
        issues: article_issues.first(10)  # Limit issues per article
      }
    end

    # Generate summary report
    def summary
      return "No issues found." if @issues.empty?

      type_counts = Hash.new(0)
      @issues.each do |article|
        article[:issues].each do |issue|
          type_counts[issue[:type]] += 1
        end
      end

      {
        total_articles_with_issues: @issues.size,
        issues_by_type: type_counts.sort_by { |_, v| -v }.to_h,
        sample_issues: @issues.first(10)
      }
    end

    # Save issues to file
    def save(path)
      FileUtils.mkdir_p(File.dirname(path))

      File.open(path, "w") do |f|
        @issues.each do |issue|
          f.puts(JSON.generate(issue))
        end
      end

      # Also save summary
      summary_path = path.sub(/\.jsonl$/, "_summary.json")
      File.open(summary_path, "w") do |f|
        f.write(JSON.pretty_generate(summary))
      end

      puts "Issues saved to: #{path}"
      puts "Summary saved to: #{summary_path}"
    end

    private

    def redirect?(text)
      text =~ /\A\s*#redirect/i || text =~ /\A\s*#転送/i
    end

    def extract_context(text, match)
      index = text.index(match)
      return match unless index

      start_pos = [index - 50, 0].max
      end_pos = [index + match.length + 50, text.length].min

      context = text[start_pos...end_pos]
      context = "..." + context if start_pos > 0
      context = context + "..." if end_pos < text.length
      context.gsub(/\n/, "\\n")
    end
  end
end
