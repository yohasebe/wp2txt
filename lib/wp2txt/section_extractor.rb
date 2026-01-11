# frozen_string_literal: true

require "yaml"

module Wp2txt
  # SectionExtractor handles extraction of sections from Wikipedia articles
  # Supports both metadata extraction (headings only) and content extraction
  class SectionExtractor
    # Reserved keyword for the lead section (text before first heading)
    SUMMARY_KEY = "summary"

    # Default section aliases (canonical name => array of aliases)
    DEFAULT_ALIASES = {
      "Plot" => ["Synopsis"],
      "Reception" => ["Critical reception"]
    }.freeze

    # Track which actual headings matched which requested sections
    attr_reader :matched_sections

    # @param target_sections [Array<String>, nil] List of section names to extract (nil = all)
    # @param options [Hash] Extraction options
    # @option options [Integer] :min_length Minimum section length (default: 0)
    # @option options [Boolean] :skip_empty Skip articles with no matching sections (default: false)
    # @option options [Hash] :aliases Custom section aliases (merged with defaults)
    # @option options [String] :alias_file Path to YAML file with custom aliases
    # @option options [Boolean] :use_aliases Enable alias matching (default: true)
    # @option options [Boolean] :track_matches Track which headings matched (default: false)
    def initialize(target_sections = nil, options = {})
      @targets = normalize_targets(target_sections)
      @min_length = options[:min_length] || 0
      @skip_empty = options[:skip_empty] || false
      @use_aliases = options.fetch(:use_aliases, true)
      @track_matches = options[:track_matches] || false
      @matched_sections = {}
      @aliases = build_aliases(options[:aliases], options[:alias_file])
    end

    # Load aliases from YAML file
    # @param file_path [String] Path to YAML file
    # @return [Hash] Aliases hash (canonical => [aliases])
    def self.load_aliases_from_file(file_path)
      return {} unless file_path && File.exist?(file_path)

      data = YAML.load_file(file_path)
      return {} unless data.is_a?(Hash)

      # Normalize: ensure values are arrays
      data.transform_values { |v| Array(v) }
    rescue Psych::SyntaxError, Errno::ENOENT
      {}
    end

    # Extract section headings from article (for --metadata-only)
    # @param article [Article] The article to extract from
    # @return [Array<String>] List of section heading names
    def extract_headings(article)
      headings = []
      article.elements.each do |element|
        next unless element[0] == :mw_heading

        heading_text = clean_heading_text(element[1])
        headings << heading_text unless heading_text.empty?
      end
      headings
    end

    # Extract section headings with levels (for detailed analysis)
    # @param article [Article] The article to extract from
    # @return [Array<Hash>] List of {name:, level:} hashes
    def extract_headings_with_levels(article)
      headings = []
      article.elements.each do |element|
        next unless element[0] == :mw_heading

        heading_text = clean_heading_text(element[1])
        level = element[2] || 2
        headings << { name: heading_text, level: level } unless heading_text.empty?
      end
      headings
    end

    # Extract summary (lead section) from article
    # @param article [Article] The article to extract from
    # @param config [Hash] Formatting configuration
    # @return [String, nil] The summary text or nil if empty
    def extract_summary(article, config = {})
      contents = +""
      article.elements.each do |element|
        # Stop at first heading
        break if element[0] == :mw_heading

        # Skip non-content elements
        next if %i[mw_blank mw_redirect mw_comment].include?(element[0])

        content = element[1].to_s
        contents << content
      end

      result = contents.strip
      result.empty? ? nil : result
    end

    # Extract specified sections from article
    # @param article [Article] The article to extract from
    # @param config [Hash] Formatting configuration
    # @return [Hash] Section name => content (nil if not found)
    def extract_sections(article, config = {})
      return {} if @targets.nil? || @targets.empty?

      # Reset matched sections for this article
      @matched_sections = {}

      result = {}

      # Initialize all targets with nil
      @targets.each { |t| result[t] = nil }

      # Handle summary separately
      if @targets.include?(SUMMARY_KEY)
        summary = extract_summary(article, config)
        result[SUMMARY_KEY] = apply_min_length_filter(summary)
      end

      # Extract other sections
      current_section = nil
      current_level = nil
      buffer = +""

      article.elements.each do |element|
        type = element[0]
        content = element[1]
        level = element[2]

        if type == :mw_heading
          # Save previous section if it was a target
          if current_section
            canonical = find_canonical_name(current_section)
            if canonical && canonical != SUMMARY_KEY
              result[canonical] = apply_min_length_filter(buffer.strip)
            end
          end

          # Check if this heading is a target
          heading_text = clean_heading_text(content)
          canonical = find_canonical_name(heading_text)

          if canonical && canonical != SUMMARY_KEY
            current_section = heading_text
            current_level = level || 2
            buffer = +""
          elsif current_level && (level.nil? || level <= current_level)
            # Same or higher level heading ends current section
            current_section = nil
            current_level = nil
            buffer = +""
          end
        elsif current_section
          # Accumulate content for current section
          buffer << content.to_s
        end
      end

      # Save final section
      if current_section
        canonical = find_canonical_name(current_section)
        if canonical && canonical != SUMMARY_KEY
          result[canonical] = apply_min_length_filter(buffer.strip)
        end
      end

      result
    end

    # Check if article has any matching sections
    # @param article [Article] The article to check
    # @return [Boolean] true if at least one target section exists
    def has_matching_sections?(article)
      return true if @targets.nil? || @targets.empty?

      # Check summary
      if @targets.include?(SUMMARY_KEY)
        summary = extract_summary(article)
        return true if summary && !summary.empty?
      end

      # Check headings (don't record matches during check)
      headings = extract_headings(article)
      headings.any? { |h| find_canonical_name(h, record_match: false) }
    end

    # Check if extraction should be skipped for this article
    # @param article [Article] The article to check
    # @return [Boolean] true if article should be skipped
    def should_skip?(article)
      return false unless @skip_empty
      !has_matching_sections?(article)
    end

    private

    # Normalize target section names
    def normalize_targets(targets)
      return nil if targets.nil?

      Array(targets).map { |t| t.to_s.strip }.reject(&:empty?)
    end

    # Build aliases hash from options, file, and defaults
    def build_aliases(custom_aliases, alias_file = nil)
      return {} unless @use_aliases

      aliases = DEFAULT_ALIASES.dup

      # Load from file if specified
      if alias_file
        file_aliases = self.class.load_aliases_from_file(alias_file)
        aliases.merge!(file_aliases)
      end

      # Merge inline custom aliases
      aliases.merge!(custom_aliases) if custom_aliases.is_a?(Hash)
      aliases
    end

    # Clean heading text by removing = markers and whitespace
    def clean_heading_text(text)
      text.to_s.gsub(/^[\s\n]*=+\s*/, "").gsub(/\s*=+[\s\n]*$/, "").strip
    end

    # Find canonical name for a heading (handles aliases)
    # @param heading [String] The actual heading text from the article
    # @param record_match [Boolean] Whether to record the match for tracking
    # @return [String, nil] The canonical (requested) section name, or nil
    def find_canonical_name(heading, record_match: true)
      return nil if heading.nil? || heading.empty?
      return nil if @targets.nil?

      heading_lower = heading.downcase.strip

      # Direct match
      @targets.each do |target|
        if target.downcase == heading_lower
          # Record direct match (only if heading differs in case)
          if @track_matches && record_match && target != heading
            @matched_sections[target] = heading
          end
          return target
        end
      end

      # Alias match
      return nil unless @use_aliases

      @aliases.each do |canonical, alias_list|
        next unless @targets.any? { |t| t.downcase == canonical.downcase }

        if alias_list.any? { |a| a.downcase == heading_lower }
          # Return the target that matches canonical
          target = @targets.find { |t| t.downcase == canonical.downcase }
          # Record alias match
          if @track_matches && record_match && target
            @matched_sections[target] = heading
          end
          return target
        end
      end

      nil
    end

    # Apply minimum length filter
    def apply_min_length_filter(text)
      return nil if text.nil?
      return nil if @min_length > 0 && text.length < @min_length

      text
    end
  end

  # Collects section heading statistics across multiple articles
  # Used for --section-stats mode
  class SectionStatsCollector
    attr_reader :total_articles, :section_counts

    def initialize
      @total_articles = 0
      @section_counts = Hash.new(0)
      @extractor = SectionExtractor.new
    end

    # Process an article and collect section heading statistics
    # @param article [Article] The article to process
    def process(article)
      @total_articles += 1
      headings = @extractor.extract_headings(article)
      headings.each { |h| @section_counts[h] += 1 }
    end

    # Get top N sections by count
    # @param n [Integer] Number of sections to return (default: 50)
    # @return [Array<Hash>] Array of {name:, count:} hashes
    def top_sections(n = 50)
      @section_counts
        .sort_by { |_name, count| -count }
        .first(n)
        .map { |name, count| { "name" => name, "count" => count } }
    end

    # Generate statistics output as a hash
    # @param top_n [Integer] Number of top sections to include
    # @return [Hash] Statistics hash
    def to_hash(top_n: 50)
      {
        "total_articles" => @total_articles,
        "section_counts" => @section_counts.sort_by { |_k, v| -v }.to_h,
        "top_sections" => top_sections(top_n)
      }
    end

    # Generate JSON output
    # @param top_n [Integer] Number of top sections to include
    # @return [String] JSON string
    def to_json(top_n: 50)
      require "json"
      JSON.pretty_generate(to_hash(top_n: top_n))
    end
  end
end
