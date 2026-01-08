# frozen_string_literal: true

require "optimist"
require_relative "version"
require_relative "multistream"

module Wp2txt
  # CLI option parsing and validation
  module CLI
    # Default cache directory
    DEFAULT_CACHE_DIR = File.expand_path("~/.wp2txt/cache")

    # Maximum number of processors for parallel processing
    MAX_PROCESSORS = 8

    class << self
      # Parse command line options
      # @param args [Array<String>] Command line arguments
      # @return [Hash] Parsed options
      def parse_options(args)
        opts = Optimist.options(args) do
          version Wp2txt::VERSION
          banner <<~BANNER
            WP2TXT extracts plain text data from Wikipedia dump files.

            Usage:
              wp2txt --lang=ja [options]           # Auto-download and process
              wp2txt --input=FILE [options]        # Process local file
              wp2txt --cache-status                # Show cache status
              wp2txt --cache-clear [--lang=CODE]   # Clear cache

            Options:
          BANNER

          # Input source (one of --input or --lang required, unless cache operations)
          opt :input, "Path to compressed file (bz2) or XML file",
              type: String, short: "-i"
          opt :lang, "Wikipedia language code (e.g., ja, en, de) for auto-download",
              type: String, short: "-L"
          opt :articles, "Specific article titles to extract (comma-separated, requires --lang)",
              type: String, short: "-A"

          # Output options
          opt :output_dir, "Path to output directory",
              default: Dir.pwd, type: String, short: "-o"
          opt :format, "Output format: text or json (JSONL)",
              default: "text", short: "-j"

          # Cache management
          opt :cache_dir, "Cache directory for downloaded dumps",
              default: DEFAULT_CACHE_DIR, type: String
          opt :cache_status, "Show cache status and exit",
              default: false
          opt :cache_clear, "Clear cache and exit",
              default: false

          # Processing options
          opt :category, "Show article category information",
              default: true, short: "-a"
          opt :category_only, "Extract only article title and categories",
              default: false, short: "-g"
          opt :summary_only, "Extract only title, categories, and summary",
              default: false, short: "-s"
          opt :file_size, "Approximate size (in MB) of each output file (0 for single file)",
              default: 10, short: "-f"
          opt :num_procs, "Number of parallel processes (up to #{MAX_PROCESSORS})",
              type: Integer, short: "-n"
          opt :title, "Keep page titles in output",
              default: true, short: "-t"
          opt :heading, "Keep section titles in output",
              default: true, short: "-d"
          opt :list, "Keep unprocessed list items in output",
              default: false, short: "-l"
          opt :ref, "Keep reference notations [ref]...[/ref]",
              default: false, short: "-r"
          opt :redirect, "Show redirect destination",
              default: false, short: "-e"
          opt :marker, "Show symbols prefixed to list items",
              default: true, short: "-m"
          opt :markers, "Content type markers (math,code,chem,table,score,timeline,graph,ipa or 'all'/'none')",
              default: "all", short: "-k"
          opt :extract_citations, "Extract formatted citations instead of removing them",
              default: false, short: "-C"
          opt :bz2_gem, "Use Ruby's bzip2-ruby gem instead of system command",
              default: false, short: "-b"

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
        # Cache operations don't need input/lang
        return if opts[:cache_status] || opts[:cache_clear]

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
        DEFAULT_CACHE_DIR
      end
    end
  end
end
