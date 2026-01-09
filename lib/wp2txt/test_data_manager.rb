# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "constants"
require_relative "multistream"
require_relative "regex"

module Wp2txt
  # Manages test data extraction and caching from Wikipedia dumps
  class TestDataManager
    CACHE_DIR = "tmp/test_cache"

    # Data file paths
    TIERS_PATH = File.join(__dir__, "data", "language_tiers.json")
    METADATA_PATH = File.join(__dir__, "data", "language_metadata.json")

    # Legacy test languages (for backward compatibility)
    # Use CORE_LANGUAGES from constants.rb for consistency
    TEST_LANGUAGES = Wp2txt::CORE_LANGUAGES.first(6).freeze

    # Test levels with article counts (legacy - tier system overrides these)
    TEST_LEVELS = {
      unit: 500,
      integration: 5000,
      validation: :all
    }.freeze

    attr_reader :lang, :level, :cache_dir

    # Load tier configuration
    def self.load_tiers
      return @tiers if @tiers

      if File.exist?(TIERS_PATH)
        @tiers = JSON.parse(File.read(TIERS_PATH))
      else
        # Fallback to legacy configuration
        @tiers = {
          "tiers" => {
            "tier1" => { "languages" => { "en" => 10000, "ja" => 5000 } },
            "tier2" => { "languages" => { "zh" => 1000, "ru" => 1000, "ar" => 1000, "ko" => 1000 } },
            "tier3" => { "default_sample_size" => 50, "languages" => [] },
            "tier4" => { "default_sample_size" => 10, "languages" => "_remaining" }
          }
        }
      end
      @tiers
    end

    # Load language metadata
    def self.load_metadata
      return @metadata if @metadata

      if File.exist?(METADATA_PATH)
        @metadata = JSON.parse(File.read(METADATA_PATH))
      else
        @metadata = { "languages" => {} }
      end
      @metadata
    end

    # Get all available languages from metadata
    def self.available_languages
      load_metadata.dig("languages")&.keys || []
    end

    # Get tier info for a language
    def self.tier_for(lang)
      lang_str = lang.to_s
      tiers = load_tiers["tiers"]

      # Check tier1 and tier2 (explicit language mappings)
      %w[tier1 tier2].each do |tier_name|
        tier = tiers[tier_name]
        if tier["languages"].is_a?(Hash) && tier["languages"].key?(lang_str)
          return { tier: tier_name, sample_size: tier["languages"][lang_str] }
        end
      end

      # Check tier3 (explicit list)
      tier3 = tiers["tier3"]
      if tier3["languages"].is_a?(Array) && tier3["languages"].include?(lang_str)
        return { tier: "tier3", sample_size: tier3["default_sample_size"] }
      end

      # Default to tier4 (remaining languages)
      tier4 = tiers["tier4"]
      { tier: "tier4", sample_size: tier4["default_sample_size"] }
    end

    # Get sample size for a language
    def self.sample_size_for(lang)
      tier_for(lang)[:sample_size]
    end

    # Get all languages in a specific tier
    def self.languages_in_tier(tier_name)
      tiers = load_tiers["tiers"]
      tier = tiers[tier_name]
      return [] unless tier

      case tier_name
      when "tier1", "tier2"
        tier["languages"].keys.map(&:to_sym)
      when "tier3"
        tier["languages"].map(&:to_sym)
      when "tier4"
        # All remaining languages not in tier1-3
        all_langs = available_languages.map(&:to_sym)
        tier1_2_3 = languages_in_tier("tier1") + languages_in_tier("tier2") + languages_in_tier("tier3")
        all_langs - tier1_2_3
      else
        []
      end
    end

    # Get all languages across all tiers
    def self.all_tier_languages
      %w[tier1 tier2 tier3 tier4].flat_map { |t| languages_in_tier(t) }.uniq
    end

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
      Wp2txt.file_fresh?(cache_path, Wp2txt::DEFAULT_TEST_DATA_EXPIRY_DAYS)
    end

    # Path to cached articles JSON
    def cache_path
      article_count = target_article_count
      count_str = article_count == :all ? "all" : article_count.to_s
      File.join(@cache_dir, @lang.to_s, "#{@level}_#{count_str}_#{dump_date}.json")
    end

    # Get target article count based on tier or level
    def target_article_count
      if @level == :validation
        :all
      elsif @level == :tier
        # Use tier-based sample size
        self.class.sample_size_for(@lang)
      else
        # Legacy level-based count
        TEST_LEVELS[@level] || 500
      end
    end

    # Get dump date being used
    def dump_date
      @dump_manager.latest_dump_date
    end

    # Get summary of available test data (legacy - for TEST_LANGUAGES only)
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

    # Get tier-based status for all configured languages (with optional progress output)
    def self.tier_status(show_progress: false)
      status = { tier1: {}, tier2: {}, tier3: {}, tier4: {} }

      %w[tier1 tier2 tier3 tier4].each do |tier_name|
        langs = languages_in_tier(tier_name)
        if show_progress
          puts "Checking #{tier_name}... (#{langs.size} languages)"
          $stdout.flush
        end

        langs.each_with_index do |lang, idx|
          if show_progress && (idx + 1) % 10 == 0
            print "\r  #{idx + 1}/#{langs.size} checked"
            $stdout.flush
          end

          begin
            manager = new(lang, level: :tier)
            status[tier_name.to_sym][lang] = {
              sample_size: sample_size_for(lang),
              cached: File.exist?(manager.cache_path),
              fresh: manager.cache_fresh?
            }
          rescue ArgumentError, RuntimeError => e
            # Language not available or no dumps found
            status[tier_name.to_sym][lang] = { error: e.message.split("\n").first }
          end
        end

        puts "\r  #{langs.size}/#{langs.size} checked" if show_progress
      end

      status
    end

    # Print tier status summary
    def self.print_tier_status
      puts "=== Tier-based Test Data Status ==="
      puts "Checking languages (this may take a moment)..."
      puts
      $stdout.flush

      status = tier_status(show_progress: true)

      puts
      puts "=== Summary ==="
      puts

      %i[tier1 tier2 tier3 tier4].each do |tier_name|
        tier_data = status[tier_name]
        cached_count = tier_data.count { |_, v| v[:cached] }
        fresh_count = tier_data.count { |_, v| v[:fresh] }
        error_count = tier_data.count { |_, v| v[:error] }

        puts "#{tier_name.to_s.upcase} (#{tier_data.size} languages):"
        puts "  Cached: #{cached_count}, Fresh: #{fresh_count}, Errors: #{error_count}"

        # Show details for tier1 and tier2
        if %i[tier1 tier2].include?(tier_name)
          tier_data.each do |lang, info|
            if info[:error]
              puts "    #{lang}: ⚠️  #{info[:error]}"
            else
              status_icon = info[:fresh] ? "✅" : (info[:cached] ? "⚠️" : "❌")
              puts "    #{lang}: #{status_icon} (#{info[:sample_size]} articles)"
            end
          end
        end
        puts
      end
    end

    private

    def validate_inputs!
      # For tier level, accept any language in metadata or fallback to tier4
      valid_levels = TEST_LEVELS.keys + [:tier]
      raise ArgumentError, "Unknown level: #{@level}" unless valid_levels.include?(@level)

      # For legacy levels, only accept TEST_LANGUAGES
      if @level != :tier && !TEST_LANGUAGES.include?(@lang)
        raise ArgumentError, "Unknown language: #{@lang}. Use level: :tier for non-core languages."
      end

      # For tier level, check if language exists in metadata (or allow any as tier4)
      # Languages not in metadata will still work but may fail at download
    end

    def ensure_cache_fresh
      return if cache_fresh?

      puts "Cache stale or missing for #{@lang}/#{@level}, extracting..."
      $stdout.flush
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

      # Create multistream reader (this parses the index which can take time)
      print "Loading index file..."
      $stdout.flush
      reader = MultistreamReader.new(multistream_path, index_path)
      puts " done (#{reader.index.size} articles, #{reader.index.stream_offsets.size} streams)"

      # Determine how many articles to extract
      count = target_article_count
      count = reader.index.size if count == :all

      # Extract articles
      puts "Extracting #{count} articles for #{@lang}/#{@level}..."
      $stdout.flush
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
          $stdout.flush
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
      # Only match specific HTML tags that might be remnants (not math like a<b)
      html_tags: /<(math|nowiki|gallery|source|code|syntaxhighlight|pre|poem|score|html|div|span|table|font|center|blockquote|templatestyles)[\s>\/]/i,
      ref_tags: /<ref|<\/ref>/i,
      table_markup: /\{\||\|\}/,

      # Output quality
      excessive_newlines: /\n{4,}/,
      empty_parens: /\(\s*\)|（\s*）/,
      pipe_remnants: /\|{2,}|\|\s*$/,
      # Note: 【 】 with space is intentional Japanese notation, so only match truly empty
      empty_brackets: /\[\]|【】/,

      # Encoding issues
      replacement_char: /\uFFFD/,
      null_bytes: /\x00/,

      # Suspicious patterns
      magic_words: /__[A-Z]+__/,
      # Require at least 2 chars to avoid false positives like A&M; or D&D;
      html_entities: /&[a-z]{2,};|&#\d+;/i
    }.freeze

    attr_reader :issues, :skipped_count, :total_analyzed

    def initialize(skip_non_articles: true)
      @issues = []
      @skip_non_articles = skip_non_articles
      @skipped_count = 0
      @total_analyzed = 0
      @skipped_titles = []
    end

    # Analyze an article for issues
    def analyze(title:, input:, output:, processing_time: nil)
      # Skip non-article pages (Wikipedia:, Template:, Portal:, etc.)
      if @skip_non_articles && !Wp2txt.article_page?(title)
        @skipped_count += 1
        @skipped_titles << title if @skipped_titles.size < 10  # Keep sample of skipped titles
        return
      end

      @total_analyzed += 1
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
      type_counts = Hash.new(0)
      @issues.each do |article|
        article[:issues].each do |issue|
          type_counts[issue[:type]] += 1
        end
      end

      result = {
        total_analyzed: @total_analyzed,
        skipped_non_articles: @skipped_count,
        total_articles_with_issues: @issues.size,
        issue_rate: @total_analyzed > 0 ? (@issues.size.to_f / @total_analyzed * 100).round(2) : 0,
        issues_by_type: type_counts.sort_by { |_, v| -v }.to_h,
        sample_issues: @issues.first(10)
      }

      # Add sample of skipped titles for reference
      result[:skipped_samples] = @skipped_titles unless @skipped_titles.empty?

      result
    end

    # Human-readable summary string
    def summary_text
      s = summary
      lines = []
      lines << "Analyzed: #{s[:total_analyzed]} articles (#{s[:skipped_non_articles]} non-article pages skipped)"
      lines << "Issues: #{s[:total_articles_with_issues]} (#{s[:issue_rate]}%)"
      if s[:issues_by_type].any?
        lines << "By type:"
        s[:issues_by_type].each { |type, count| lines << "  #{type}: #{count}" }
      end
      lines.join("\n")
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
      # Use multilingual redirect keywords from regex.rb
      text =~ /\A\s*#(?:#{REDIRECT_KEYWORDS})/i
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
