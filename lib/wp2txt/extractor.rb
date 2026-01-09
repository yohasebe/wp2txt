# frozen_string_literal: true

require_relative "multistream"
require_relative "cli"

module Wp2txt
  # Article extraction utilities for WpApp
  module Extractor
    # Exit codes
    EXIT_SUCCESS = 0
    EXIT_ERROR = 1
    EXIT_PARTIAL = 2

    # Extract specific articles by title
    def extract_specific_articles(opts)
      lang = opts[:lang]
      cache_dir = opts[:cache_dir]
      article_titles = Wp2txt::CLI.parse_article_list(opts[:articles])
      app_config = Wp2txt::CLI.config
      force_update = opts[:update_cache]
      total_steps = 4
      start_time = Time.now

      # Mode banner
      articles_display = article_titles.size > 3 ? "#{article_titles.first(3).join(', ')}... (#{article_titles.size} total)" : article_titles.join(", ")
      print_mode_banner("Article Extraction", {
        "Language" => lang,
        "Articles" => articles_display,
        "Output" => opts[:output_dir]
      })

      # Create dump manager
      manager = Wp2txt::DumpManager.new(
        lang,
        cache_dir: cache_dir,
        dump_expiry_days: app_config.dump_expiry_days
      )

      # Step 1: Download index
      print_header("Downloading index", step: 1, total_steps: total_steps)
      index_path = manager.download_index(force: force_update)

      # Step 2: Load index and find articles
      print_header("Locating articles", step: 2, total_steps: total_steps)
      spinner = create_spinner("Parsing index...")
      spinner.auto_spin
      index = Wp2txt::MultistreamIndex.new(index_path)
      spinner.success(pastel.green("#{index.size} articles indexed"))
      puts

      # Find requested articles
      found_articles = []
      not_found = []

      article_titles.each do |title|
        entry = index.find_by_title(title)
        if entry
          found_articles << entry
          print_list_item("#{title}", status: :success)
        else
          not_found << title
          print_list_item("#{title} (not found)", status: :error)
        end
      end

      if found_articles.empty?
        puts unless quiet?
        print_error("No articles found. Please check the titles.")
        return EXIT_ERROR
      end

      # Step 3: Download streams
      streams_needed = found_articles.map { |e| e[:offset] }.uniq.sort
      print_header("Downloading data (#{streams_needed.size} streams)", step: 3, total_steps: total_steps)
      multistream_path = download_partial_streams(manager, index, streams_needed, force: force_update)

      # Create multistream reader
      reader = Wp2txt::MultistreamReader.new(multistream_path, index_path)

      # Build config for processing
      format = opts[:format].to_s.downcase.to_sym
      config = build_extraction_config(opts, format)

      # Create output writer
      base_name = "#{lang}wiki_articles"
      writer = OutputWriter.new(
        output_dir: opts[:output_dir],
        base_name: base_name,
        format: format,
        file_size_mb: opts[:file_size]
      )

      # Step 4: Extract articles
      print_header("Extracting articles", step: 4, total_steps: total_steps)
      extracted_count = 0
      extraction_failures = []

      found_articles.each do |entry|
        title = entry[:title]
        page = reader.extract_article(title)

        if page
          article = Article.new(page[:text], page[:title], !config[:marker])
          result = format_article(article, config)
          writer.write(result)
          extracted_count += 1
          print_list_item("#{title}", status: :success)
        else
          extraction_failures << title
          print_list_item("#{title} (extraction failed)", status: :warning)
        end
      end

      # Close output
      output_files = writer.close
      total_time = Time.now - start_time

      # Summary
      has_issues = not_found.any? || extraction_failures.any?
      status = has_issues ? :warning : :success

      print_summary("Extraction Complete", {
        "Extracted" => "#{extracted_count}/#{article_titles.size}",
        "Output files" => output_files.size.to_s,
        "Total time" => format_duration(total_time)
      }, status: status)

      if not_found.any?
        puts unless quiet?
        print_warning("Not found in index (#{not_found.size}):")
        not_found.each { |t| print_list_item(t, status: :error) }
      end

      puts unless quiet?
      puts pastel.dim("Output files:") unless quiet?
      output_files.each { |f| print_list_item(f, status: :success) }

      # Return appropriate exit code
      has_issues ? EXIT_PARTIAL : EXIT_SUCCESS
    end

    # Download only the streams containing the requested articles
    # @param manager [DumpManager] The dump manager
    # @param index [MultistreamIndex] The multistream index
    # @param stream_offsets [Array<Integer>] Byte offsets of streams to download
    # @param force [Boolean] Force re-download even if cached
    def download_partial_streams(manager, index, stream_offsets, force: false)
      # Calculate how many streams are needed
      all_offsets = index.stream_offsets
      max_offset_needed = stream_offsets.max

      # Find the index of the highest needed stream
      max_idx = all_offsets.index(max_offset_needed)
      if max_idx.nil? || max_idx >= all_offsets.size - 1
        # Need full file for last stream
        return manager.download_multistream(force: force)
      end

      # Request partial download (DumpManager handles caching logic)
      stream_count = max_idx + 1
      manager.download_multistream(max_streams: stream_count, force: force)
    end

    # Show download estimate before confirmation
    # @param manager [DumpManager] The dump manager
    # @param app_config [Config] Application configuration
    # @return [Boolean] True if cache is stale and user should be warned
    def show_download_estimate(manager, app_config = nil)
      puts pastel.dim("Download status:")

      # Check index cache
      index_path = manager.cached_index_path
      index_cached = File.exist?(index_path)
      cache_is_stale = false

      if index_cached
        index_size = format_size(File.size(index_path))
        age_days = manager.cache_age_days
        mtime = manager.cache_mtime
        expiry_days = app_config&.dump_expiry_days || manager.dump_expiry_days

        # Format cache date
        cache_date_str = mtime ? mtime.strftime("%Y-%m-%d") : "unknown"

        # Check if stale
        cache_is_stale = age_days && age_days > expiry_days

        if cache_is_stale
          age_str = age_days >= 1 ? "#{age_days.round(0)} days ago" : "today"
          print_list_item("Index: #{pastel.yellow('cached')} (#{index_size}, #{cache_date_str} - #{age_str})", status: :warning)
          print_list_item("  Cache is older than #{expiry_days} days (recommended refresh)", status: :warning, indent: 2)
        else
          age_str = age_days && age_days >= 1 ? "#{age_days.round(0)} days ago" : "today"
          print_list_item("Index: #{pastel.green('cached')} (#{index_size}, #{cache_date_str} - #{age_str})", status: :success)
        end
      else
        print_list_item("Index: #{pastel.yellow('download required')}", status: :warning)
      end

      # Check multistream cache
      full_path = manager.cached_multistream_path
      full_cached = File.exist?(full_path)

      if full_cached
        dump_size = format_size(File.size(full_path))
        dump_date_str = File.mtime(full_path).strftime("%Y-%m-%d")
        dump_age = ((Time.now - File.mtime(full_path)) / 86400).round(0)
        dump_age_str = dump_age >= 1 ? "#{dump_age} days ago" : "today"

        if cache_is_stale
          print_list_item("Dump: #{pastel.yellow('cached')} (#{dump_size}, #{dump_date_str} - #{dump_age_str})", status: :warning)
        else
          print_list_item("Dump: #{pastel.green('cached')} (#{dump_size}, #{dump_date_str} - #{dump_age_str})", status: :success)
        end
      else
        # Check for partial downloads
        partial = manager.find_suitable_partial_cache(1)
        if partial
          partial_size = format_size(File.size(partial))
          partial_date = File.mtime(partial).strftime("%Y-%m-%d")
          print_list_item("Dump: #{pastel.cyan('partial cached')} (#{partial_size}, #{partial_date})", status: :success)
          print_list_item("  Additional download may be required depending on article locations", status: :pending)
        else
          print_list_item("Dump: #{pastel.yellow('download required')} (several GB)", status: :warning)
        end
      end

      if cache_is_stale
        puts
        print_warning("Cache is stale. Use --update-cache to force refresh.")
      end

      puts
      cache_is_stale
    end

    # Build config hash for article extraction
    def build_extraction_config(opts, format)
      config = {
        format: format,
        num_procs: 1,  # Single-threaded for article extraction
        file_size: opts[:file_size],
        bz2_gem: opts[:bz2_gem]
      }

      %i[title list heading table redirect multiline category category_only
         summary_only marker extract_citations].each do |opt|
        config[opt] = opts[opt]
      end

      config[:markers] = parse_markers_option(opts[:markers])
      config
    end

    # Extract articles from a Wikipedia category
    def extract_category_articles(opts)
      lang = opts[:lang]
      category = opts[:from_category]
      max_depth = opts[:depth]
      cache_dir = opts[:cache_dir]
      dry_run = opts[:dry_run]
      skip_confirm = opts[:yes]
      total_steps = 6
      start_time = Time.now

      # Mode banner
      print_mode_banner("Category Extraction", {
        "Language" => lang,
        "Category" => category,
        "Depth" => max_depth,
        "Output" => opts[:output_dir]
      })

      # Get config values
      app_config = Wp2txt::CLI.config

      # Create category fetcher
      fetcher = Wp2txt::CategoryFetcher.new(
        lang, category,
        max_depth: max_depth,
        cache_expiry_days: app_config.category_expiry_days
      )

      # Step 1: Fetch preview
      print_header("Scanning category", step: 1, total_steps: total_steps)
      spinner = create_spinner("Fetching category information...")
      spinner.auto_spin

      begin
        preview = fetcher.fetch_preview
        spinner.success(pastel.green("Done!"))
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError, JSON::ParserError, IOError => e
        spinner.error(pastel.red("Failed!"))
        print_error("Error fetching category: #{e.message}")
        return EXIT_ERROR
      end

      # Display preview
      print_subheader("Category Preview")
      print_info("Category", preview[:category])
      print_info("Depth", preview[:depth].to_s)
      puts

      if preview[:subcategories] && !preview[:subcategories].empty?
        puts pastel.dim("Categories scanned:")
        preview[:subcategories].each do |subcat|
          print_list_item("#{subcat[:name]} (#{subcat[:article_count]} articles)")
        end
        puts
      end

      puts pastel.dim("Summary:")
      print_info("Subcategories", (preview[:total_subcategories] || 0).to_s, indent: 1)
      print_info("Total articles", pastel.bold(preview[:total_articles].to_s), indent: 1)
      puts

      # Check if there are any articles
      if preview[:total_articles].zero?
        print_warning("No articles found in this category.")
        return EXIT_SUCCESS  # Not an error, just empty category
      end

      # Warn about large extractions
      if preview[:total_articles] > 1000
        print_warning("Large category with #{preview[:total_articles]} articles.")
        puts pastel.yellow("  Extraction may take a long time and require significant disk space.")
        puts
      end

      # Show cache status before confirmation
      temp_manager = Wp2txt::DumpManager.new(
        lang,
        cache_dir: cache_dir,
        dump_expiry_days: app_config.dump_expiry_days
      )
      cache_stale = show_download_estimate(temp_manager, app_config)
      force_update = opts[:update_cache]

      # Dry run mode - exit here
      if dry_run
        print_info_message("Dry run mode - no articles will be extracted.")
        return EXIT_SUCCESS
      end

      # Confirmation prompt
      unless skip_confirm
        unless $stdin.tty?
          print_error("Interactive confirmation required.")
          puts pastel.red("  Use --yes to skip confirmation when running non-interactively.")
          return EXIT_ERROR
        end

        unless confirm?("Proceed with extraction?")
          puts "Extraction cancelled."
          return EXIT_SUCCESS  # User chose to cancel
        end
      end

      # Step 2: Fetch full article list
      print_header("Fetching articles from API", step: 2, total_steps: total_steps)
      spinner = create_spinner("Fetching article list...")
      spinner.auto_spin

      begin
        article_titles = fetcher.fetch_articles
        spinner.success(pastel.green("#{article_titles.size} articles"))
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError, JSON::ParserError, IOError => e
        spinner.error(pastel.red("Failed!"))
        print_error("Error fetching articles: #{e.message}")
        return EXIT_ERROR
      end

      if article_titles.empty?
        print_warning("No articles to extract.")
        return EXIT_SUCCESS  # Not an error, just empty result
      end

      # Create dump manager
      manager = Wp2txt::DumpManager.new(
        lang,
        cache_dir: cache_dir,
        dump_expiry_days: app_config.dump_expiry_days
      )

      # Step 3: Download index
      print_header("Downloading index", step: 3, total_steps: total_steps)
      index_path = manager.download_index(force: force_update)

      # Step 4: Load index and locate articles
      print_header("Locating articles in dump", step: 4, total_steps: total_steps)
      spinner = create_spinner("Parsing index...")
      spinner.auto_spin
      index = Wp2txt::MultistreamIndex.new(index_path)
      spinner.success(pastel.green("#{index.size} articles indexed"))

      # Find articles in index
      found_articles = []
      not_found = []

      article_titles.each do |title|
        entry = index.find_by_title(title)
        if entry
          found_articles << entry
        else
          not_found << title
        end
      end

      print_list_item("Found in dump: #{found_articles.size}", status: :success)
      print_list_item("Not in dump: #{not_found.size}", status: not_found.any? ? :warning : :success) if not_found.any?

      if found_articles.empty?
        print_error("No articles found in dump. The dump may be out of date.")
        return EXIT_ERROR
      end

      # Step 5: Download multistream
      streams_needed = found_articles.map { |e| e[:offset] }.uniq.sort
      print_header("Downloading data (#{streams_needed.size} streams)", step: 5, total_steps: total_steps)
      multistream_path = download_partial_streams(manager, index, streams_needed, force: force_update)

      # Create multistream reader
      reader = Wp2txt::MultistreamReader.new(multistream_path, index_path)

      # Build config
      format = opts[:format].to_s.downcase.to_sym
      config = build_extraction_config(opts, format)

      # Create output writer
      base_name = "#{lang}wiki_#{sanitize_filename(category)}"
      writer = OutputWriter.new(
        output_dir: opts[:output_dir],
        base_name: base_name,
        format: format,
        file_size_mb: opts[:file_size]
      )

      # Step 6: Extract and process articles
      print_header("Extracting articles", step: 6, total_steps: total_steps)
      total_count = found_articles.size
      bar = create_progress_bar("  Processing", total_count)

      extracted_count = 0
      extraction_start = Time.now

      found_articles.each do |entry|
        title = entry[:title]
        page = reader.extract_article(title)

        if page
          article = Article.new(page[:text], page[:title], !config[:marker])
          result = format_article(article, config)
          writer.write(result)
          extracted_count += 1
        end

        bar.advance
      end

      bar.finish
      extraction_time = Time.now - extraction_start

      # Close output
      output_files = writer.close

      # Summary
      total_time = Time.now - start_time
      status = not_found.empty? ? :success : :warning

      print_summary("Extraction Complete", {
        "Articles extracted" => "#{extracted_count}/#{article_titles.size}",
        "Output files" => output_files.size.to_s,
        "Extraction time" => format_duration(extraction_time),
        "Total time" => format_duration(total_time)
      }, status: status)

      if not_found.any?
        puts unless quiet?
        if not_found.size <= 10
          print_warning("Not found in dump (#{not_found.size}):")
          not_found.each { |t| print_list_item(t, status: :warning) }
        else
          print_warning("#{not_found.size} articles not found (may be newer than dump)")
        end
      end

      puts unless quiet?
      puts pastel.dim("Output files:") unless quiet?
      output_files.each { |f| print_list_item(f, status: :success) }

      # Return appropriate exit code
      not_found.empty? ? EXIT_SUCCESS : EXIT_PARTIAL
    end

    # Sanitize category name for use in filename
    def sanitize_filename(name)
      name.gsub(%r{[/\\:*?"<>|]}, "_").gsub(/\s+/, "_").slice(0, 50)
    end
  end
end
