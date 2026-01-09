# frozen_string_literal: true

require "etc"

module Wp2txt
  # Ractor-based parallel processing for Wikipedia article conversion
  #
  # Ractor allows true parallelism by bypassing Ruby's GVL (Global VM Lock),
  # enabling significant speedups for CPU-intensive text processing.
  #
  # REQUIREMENTS: Ruby 4.0+ (Ractor API stabilized in Ruby 4.0)
  # For Ruby 3.x, the Parallel gem is used instead (process-based parallelism).
  #
  # Performance: Typically 1.5-2x speedup with 4 workers on multi-core systems.
  #
  # Usage:
  #   pages = [["Title1", "wiki text..."], ["Title2", "wiki text..."]]
  #   results = RactorWorker.process_articles(pages, config: config)
  #
  module RactorWorker
    # Minimum Ruby version required for stable Ractor support
    MINIMUM_RUBY_VERSION = "4.0"

    # Registry of available operations
    OPERATIONS = %i[process_article double fib].freeze

    module_function

    # Check if Ractor is available and usable
    # Requires Ruby 4.0+ for stable Ractor support
    # @return [Boolean] true if Ractor can be used
    def available?
      return @available if defined?(@available)

      @available = check_ractor_available
    end

    # Internal method to check Ractor availability
    # @return [Boolean] true if Ractor can be used
    def check_ractor_available
      return false unless ruby_version_sufficient?
      return false unless defined?(Ractor)

      # Test basic Ractor functionality with Ruby 4.0 API
      r = Ractor.new { 1 + 1 }
      r.join
      r.value == 2
    rescue StandardError
      false
    end

    # Check if Ruby version meets minimum requirement
    # @return [Boolean] true if Ruby version is 4.0 or higher
    def ruby_version_sufficient?
      Gem::Version.new(RUBY_VERSION) >= Gem::Version.new(MINIMUM_RUBY_VERSION)
    end

    # Process articles in parallel using Ractor (main entry point)
    # @param pages [Array<Array>] Array of [title, text] pairs
    # @param config [Hash] Configuration options for formatting
    # @param strip_tmarker [Boolean] Whether to strip list markers
    # @param num_workers [Integer] Number of parallel Ractors (optional)
    # @return [Array<String>] Formatted article results
    def process_articles(pages, config:, strip_tmarker: false, num_workers: nil)
      items = pages.map { |title, text| [title, text, strip_tmarker] }

      parallel_process(
        items,
        operation: :process_article,
        config: config,
        num_workers: num_workers
      )
    end

    # Process items in parallel using map-join-value pattern (Ruby 4.0+)
    # @param items [Array] Items to process
    # @param operation [Symbol] Operation to perform (:process_article, :double, :fib)
    # @param config [Hash] Configuration to pass to each operation
    # @param num_workers [Integer] Max concurrent Ractors (default: optimal_workers)
    # @return [Array] Results from processing (in original order)
    def parallel_process(items, operation:, config: {}, num_workers: nil)
      batch_size = num_workers || optimal_workers
      batch_size = [batch_size, 1].max

      # Fall back to sequential if Ractor not available or single item
      unless available? && items.size > 1
        return items.map { |item| process_single(item, operation, config) }
      end

      # Freeze config for sharing across Ractors
      frozen_config = deep_freeze(config.dup)

      # Process in batches to limit concurrent Ractors
      results = []
      items.each_slice(batch_size) do |batch|
        batch_results = process_batch(batch, operation, frozen_config)
        results.concat(batch_results)
      end

      results
    rescue Ractor::Error => e
      warn "Ractor error (#{e.message}), falling back to sequential processing"
      items.map { |item| process_single(item, operation, config) }
    end

    # Process a batch using map-join-value pattern (Ruby 4.0 API)
    # @param items [Array] Items to process in this batch
    # @param operation [Symbol] Operation to perform
    # @param frozen_config [Hash] Frozen configuration hash
    # @return [Array] Results in original order
    def process_batch(items, operation, frozen_config)
      # Create one Ractor per item
      ractors = items.map.with_index do |item, idx|
        Ractor.new(item, frozen_config, operation, idx) do |it, cfg, op, i|
          result = begin
            case op
            when :process_article
              require_relative "utils"
              require_relative "regex"
              require_relative "article"
              require_relative "formatter"

              title, text, strip_tmarker = it
              formatter = Object.new
              formatter.extend(Wp2txt)
              formatter.extend(Wp2txt::Formatter)
              article = Wp2txt::Article.new(text, title, strip_tmarker)
              formatter.format_article(article, cfg)
            when :double
              it * 2
            when :fib
              fib = ->(n) { n <= 1 ? n : fib.call(n - 1) + fib.call(n - 2) }
              fib.call(it)
            else
              raise "Unknown operation: #{op}"
            end
          rescue StandardError
            nil # Return nil on error
          end
          [i, result] # Return index and result for ordering
        end
      end

      # Wait for all Ractors to complete and collect results
      collected = Array.new(items.size)
      ractors.each do |r|
        r.join
        idx, result = r.value
        collected[idx] = result
      end

      collected
    end

    # Process a single item (for fallback/sequential processing)
    # @param item [Object] Item to process
    # @param operation [Symbol] Operation to perform
    # @param config [Hash] Configuration options
    # @return [Object] Processing result
    def process_single(item, operation, config)
      case operation
      when :process_article
        require_relative "utils"
        require_relative "regex"
        require_relative "article"
        require_relative "formatter"

        title, text, strip_tmarker = item
        formatter = Object.new
        formatter.extend(Wp2txt)
        formatter.extend(Wp2txt::Formatter)
        article = Wp2txt::Article.new(text, title, strip_tmarker)
        formatter.format_article(article, config)
      when :double
        item * 2
      when :fib
        fib = ->(n) { n <= 1 ? n : fib.call(n - 1) + fib.call(n - 2) }
        fib.call(item)
      else
        raise "Unknown operation: #{operation}"
      end
    end

    # Calculate optimal number of workers based on CPU cores
    # @return [Integer] Recommended concurrency level
    def optimal_workers
      cores = Etc.nprocessors
      case cores
      when 1..4 then cores
      when 5..8 then cores - 1
      else (cores * 0.8).to_i
      end
    end

    # Deep freeze an object for Ractor sharing
    # @param obj [Object] Object to freeze
    # @return [Object] The frozen object
    def deep_freeze(obj)
      case obj
      when Hash
        obj.transform_keys { |k| deep_freeze(k) }
           .transform_values { |v| deep_freeze(v) }
           .freeze
      when Array
        obj.map { |v| deep_freeze(v) }.freeze
      when String
        obj.frozen? ? obj : obj.dup.freeze
      when Symbol, Integer, Float, TrueClass, FalseClass, NilClass
        obj
      else
        obj.freeze rescue obj
      end
    end
  end
end
