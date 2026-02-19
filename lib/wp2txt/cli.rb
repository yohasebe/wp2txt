# frozen_string_literal: true

require "optimist"
require_relative "version"
require_relative "multistream"
require_relative "config"
require_relative "memory_monitor"

module Wp2txt
  # CLI option parsing and validation
  module CLI
    class << self
      # Get the optimal number of processors for this system
      # Based on CPU cores and available memory
      # @return [Integer] Optimal number of parallel processes
      def max_processors
        MemoryMonitor.optimal_processes
      end

      # Load configuration
      # @return [Config] Configuration object
      def load_config(config_path = nil)
        path = config_path || Config.default_path
        @config = Config.load(path)
      end

      # Get current config (lazy load)
      # @return [Config] Configuration object
      def config
        @config ||= load_config
      end

      # Parse command line options
      # @param args [Array<String>] Command line arguments
      # @return [Hash] Parsed options
      def parse_options(args)
        # Pre-load config for defaults
        cfg = config

        opts = Optimist.options(args) do
          version Wp2txt::VERSION
          banner <<~BANNER
            WP2TXT extracts plain text data from Wikipedia dump files.

            Usage:
              wp2txt --lang=ja [options]                    # Auto-download and process
              wp2txt --input=FILE [options]                 # Process local file
              wp2txt --lang=en --from-category="Cities" -o ./output  # Extract category
              wp2txt --lang=en --from-category="Cities" --dry-run    # Preview only
              wp2txt --cache-status                         # Show cache status
              wp2txt --cache-clear [--lang=CODE]            # Clear cache
              wp2txt --config-init                          # Create default config file

            Options:
          BANNER

          # Input source (one of --input or --lang required, unless cache operations)
          opt :input, "Path to compressed file (bz2) or XML file",
              type: String, short: "-i"
          opt :lang, "Wikipedia language code (e.g., ja, en, de) for auto-download",
              type: String, short: "-L"
          opt :articles, "Specific article titles to extract (comma-separated, requires --lang)",
              type: String, short: "-A"
          opt :from_category, "Extract articles from Wikipedia category (requires --lang)",
              type: String, short: "-G"
          opt :depth, "Subcategory recursion depth for --from-category (0 = no recursion)",
              default: cfg.default_depth, type: Integer, short: "-D"
          opt :yes, "Skip confirmation prompt for category extraction",
              default: false, short: "-y"
          opt :dry_run, "Preview category extraction without downloading",
              default: false
          opt :update_cache, "Force refresh of cached dump files",
              default: false, short: "-U"

          # Output options
          opt :output_dir, "Path to output directory",
              default: Dir.pwd, type: String, short: "-o"
          opt :format, "Output format: text or json (JSONL)",
              default: cfg.default_format, short: "-j"

          # Cache management
          opt :cache_dir, "Cache directory for downloaded dumps",
              default: cfg.cache_directory, type: String
          opt :cache_status, "Show cache status and exit",
              default: false
          opt :cache_clear, "Clear cache and exit",
              default: false
          opt :config_init, "Create default configuration file (~/.wp2txt/config.yml)",
              default: false
          opt :config_path, "Path to configuration file",
              type: String

          # Processing options
          opt :category, "Show article category information",
              default: true, short: "-a"
          opt :category_only, "Extract only article title and categories",
              default: false, short: "-g"
          opt :summary_only, "Extract only title, categories, and summary",
              default: false, short: "-s"
          opt :metadata_only, "Extract only title, section headings, and categories (for analysis)",
              default: false, short: "-M"

          # Section extraction options
          opt :sections, "Extract specific sections (comma-separated, 'summary' for lead text)",
              type: String, short: "-S"
          opt :section_output, "Section output mode: 'structured' (default) or 'combined'",
              default: "structured"
          opt :min_section_length, "Minimum section length in characters (shorter sections become null)",
              default: 0, type: Integer
          opt :skip_empty, "Skip articles with no matching sections",
              default: false
          opt :alias_file, "Custom section alias definitions file (YAML format)",
              type: String
          opt :no_section_aliases, "Disable section alias matching (exact match only)",
              default: false
          opt :section_stats, "Collect and output section heading statistics (JSON)",
              default: false
          opt :show_matched_sections, "Include matched_sections field in JSON output (shows actual headings)",
              default: false

          opt :file_size, "Approximate size (in MB) of each output file (0 for single file)",
              default: 10, short: "-f"
          opt :num_procs, "Number of parallel processes (auto-detected based on CPU/memory)",
              type: Integer, short: "-n"
          opt :title, "Keep page titles in output",
              default: true, short: "-t"
          opt :heading, "Keep section titles in output",
              default: true, short: "-d"
          opt :list, "Keep unprocessed list items in output",
              default: false, short: "-l"
          opt :pre, "Keep preformatted text blocks in output",
              default: false, short: "-p"
          opt :ref, "Keep reference notations [ref]...[/ref]",
              default: false, short: "-r"
          opt :redirect, "Show redirect destination",
              default: false, short: "-e"
          opt :marker, "Show symbols prefixed to list items",
              default: true, short: "-m"
          opt :markers, "Content type markers (math,code,chem,table,score,timeline,graph,ipa or 'all')",
              default: "all", short: "-k"
          opt :extract_citations, "Extract formatted citations instead of removing them",
              default: false, short: "-C"
          opt :expand_templates, "Expand common templates (birth date, convert, etc.) to readable text",
              default: true, short: "-E"
          opt :bz2_gem, "Use Ruby's bzip2-ruby gem instead of system command",
              default: false, short: "-b"
          opt :ractor, "Use Ractor for parallel processing (Ruby 4.0+, streaming mode only)",
              default: false, short: "-R"
          opt :no_turbo, "Disable turbo mode (use streaming instead, saves disk space)",
              default: false

          # Output control
          opt :quiet, "Suppress progress output (only show errors and final result)",
              default: false, short: "-q"
          opt :no_color, "Disable colored output (also respects NO_COLOR env variable)",
              default: false

          # Deprecated options
          opt :convert, "[DEPRECATED] No longer needed",
              default: true, short: "-c"
          opt :del_interfile, "[DEPRECATED] Intermediate files no longer created",
              default: false, short: "-x"
        end

        validate_options!(opts)
        opts
      end

      # Validate parsed options
      def validate_options!(opts)
        # Cache and config operations don't need input/lang
        return if opts[:cache_status] || opts[:cache_clear] || opts[:config_init]

        # Either --input or --lang is required
        if opts[:input].nil? && opts[:lang].nil?
          Optimist.die "Either --input or --lang is required"
        end

        # Cannot specify both --input and --lang
        if opts[:input] && opts[:lang]
          Optimist.die "Cannot specify both --input and --lang"
        end

        # --articles requires --lang
        if opts[:articles] && opts[:lang].nil?
          Optimist.die "--articles requires --lang"
        end

        # --articles cannot be used with --input
        if opts[:articles] && opts[:input]
          Optimist.die "--articles cannot be used with --input"
        end

        # --from-category requires --lang
        if opts[:from_category] && opts[:lang].nil?
          Optimist.die "--from-category requires --lang"
        end

        # --from-category cannot be used with --input
        if opts[:from_category] && opts[:input]
          Optimist.die "--from-category cannot be used with --input"
        end

        # --from-category cannot be used with --articles
        if opts[:from_category] && opts[:articles]
          Optimist.die "--from-category cannot be used with --articles"
        end

        # --depth must be >= 0
        if opts[:depth] < 0
          Optimist.die :depth, "must be 0 or greater"
        end

        # Warn if depth > 3 (can result in many articles)
        if opts[:depth] > 3
          warn "Warning: --depth > 3 may result in a very large number of articles"
        end

        # --dry-run only makes sense with --from-category
        if opts[:dry_run] && opts[:from_category].nil?
          Optimist.die "--dry-run requires --from-category"
        end

        # --yes only makes sense with --from-category
        if opts[:yes] && opts[:from_category].nil?
          Optimist.die "--yes requires --from-category"
        end

        # Validate --input exists
        if opts[:input] && !File.exist?(opts[:input])
          Optimist.die :input, "file does not exist"
        end

        # Validate language code
        if opts[:lang] && !valid_language_code?(opts[:lang])
          Optimist.die :lang, "invalid language code format"
        end

        # Validate output directory exists
        unless File.exist?(opts[:output_dir])
          Optimist.die :output_dir, "directory does not exist"
        end

        # Validate format
        unless %w[text json].include?(opts[:format].to_s.downcase)
          Optimist.die :format, "must be 'text' or 'json'"
        end

        # Validate file_size
        Optimist.die :file_size, "must be 0 or larger" if opts[:file_size] < 0

        # Validate --alias-file exists and is valid YAML
        if opts[:alias_file]
          unless File.exist?(opts[:alias_file])
            Optimist.die :alias_file, "file does not exist"
          end
          begin
            require "yaml"
            YAML.load_file(opts[:alias_file])
          rescue Psych::SyntaxError => e
            Optimist.die :alias_file, "invalid YAML syntax: #{e.message}"
          end
        end

        # --section-stats is a standalone mode
        if opts[:section_stats]
          if opts[:sections]
            Optimist.die "--section-stats cannot be used with --sections"
          end
          if opts[:metadata_only]
            Optimist.die "--section-stats cannot be used with --metadata-only"
          end
        end

        # --show-matched-sections only works with JSON format
        if opts[:show_matched_sections] && opts[:format].to_s.downcase != "json"
          Optimist.die "--show-matched-sections requires --format json"
        end
      end

      # Parse article list from comma-separated string
      def parse_article_list(articles_str)
        return [] if articles_str.nil? || articles_str.empty?
        articles_str.split(",").map(&:strip).reject(&:empty?)
      end

      # Check if a language code is valid
      # Valid codes: 2-10 lowercase letters (e.g., en, ja, simple, zh-yue)
      def valid_language_code?(code)
        return false if code.nil? || code.empty?
        # Allow codes like: en, ja, zh, simple, zh-yue, etc.
        code.match?(/\A[a-z]{2,10}(-[a-z]{2,10})?\z/)
      end

      # Get default cache directory
      def default_cache_dir
        Config::DEFAULT_CACHE_DIR
      end
    end
  end
end
