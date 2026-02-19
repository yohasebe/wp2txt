# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "uri"
require "openssl"
require "parallel"
require "set"
require_relative "constants"
require_relative "index_cache"
require_relative "category_cache"

module Wp2txt
  # Maximum number of retries for transient network errors
  MAX_HTTP_RETRIES = 3

  # HTTPS-aware HTTP GET helper with proper SSL verification and retry
  # @param uri [URI] The URI to request
  # @param timeout [Integer] Timeout in seconds
  # @param retries [Integer] Maximum number of retries on transient errors
  # @return [Net::HTTPResponse] The HTTP response
  def self.ssl_safe_get(uri, timeout: DEFAULT_HTTP_TIMEOUT, retries: MAX_HTTP_RETRIES)
    attempts = 0
    begin
      attempts += 1
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = timeout
      http.read_timeout = timeout

      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      request = Net::HTTP::Get.new(uri)
      http.request(request)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET,
           Errno::ECONNREFUSED, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError => e
      if attempts <= retries
        delay = 2**attempts # Exponential backoff: 2, 4, 8 seconds
        warn "  Network error (attempt #{attempts}/#{retries + 1}): #{e.message}. Retrying in #{delay}s..."
        sleep delay
        retry
      end
      raise
    end
  end
  # Manages multistream index for random access to Wikipedia dumps
  # Supports SQLite caching for fast repeated access
  class MultistreamIndex
    attr_reader :index_path, :entries_by_title, :entries_by_id, :stream_offsets

    # Initialize index with optional SQLite caching and early termination
    # @param index_path [String] Path to the bz2 index file
    # @param use_cache [Boolean] Whether to use SQLite cache (default: true)
    # @param cache_dir [String, nil] Directory for SQLite cache (default: ~/.wp2txt/cache)
    # @param target_titles [Array<String>, nil] If provided, stop parsing when all titles found
    # @param show_progress [Boolean] Whether to show progress during parsing (default: true)
    def initialize(index_path, use_cache: true, cache_dir: nil, target_titles: nil, show_progress: true)
      @index_path = index_path
      @entries_by_title = {}
      @entries_by_id = {}
      @stream_offsets = []
      @show_progress = show_progress
      @target_titles = target_titles ? Set.new(target_titles) : nil
      @found_targets = Set.new if @target_titles

      # Try to load from cache first
      if use_cache && @target_titles.nil?
        @cache = IndexCache.new(index_path, cache_dir: cache_dir)
        if load_from_cache
          return
        end
      else
        @cache = nil
      end

      # Parse index file
      load_index

      # Save to cache for future use (only if full parse completed)
      if @cache && @target_titles.nil?
        save_to_cache
      end
    end

    # Check if this index was loaded from cache
    def loaded_from_cache?
      @loaded_from_cache == true
    end

    # Check if early termination was triggered
    def early_terminated?
      @early_terminated == true
    end

    def find_by_title(title)
      @entries_by_title[title]
    end

    def find_by_id(page_id)
      @entries_by_id[page_id]
    end

    # Get all articles in a specific stream (by byte offset)
    def articles_in_stream(byte_offset)
      @entries_by_title.values.select { |e| e[:offset] == byte_offset }
    end

    # Get stream offset for a given article
    def stream_offset_for(title)
      entry = find_by_title(title)
      entry ? entry[:offset] : nil
    end

    # Get N random articles
    def random_articles(count)
      @entries_by_title.keys.sample(count)
    end

    # Get first N articles
    def first_articles(count)
      @entries_by_title.keys.first(count)
    end

    # Total number of articles
    def size
      @entries_by_title.size
    end

    private

    def load_from_cache
      return false unless @cache&.valid?

      print "  Loading index from cache..." if @show_progress
      $stdout.flush

      data = @cache.load
      return false unless data

      @entries_by_title = data[:entries_by_title]
      @entries_by_id = data[:entries_by_id]
      @stream_offsets = data[:stream_offsets]
      @loaded_from_cache = true

      puts " #{@entries_by_title.size} entries loaded" if @show_progress
      true
    end

    def save_to_cache
      return unless @cache

      print "  Saving index to cache..." if @show_progress
      $stdout.flush

      @cache.save(@entries_by_title, @stream_offsets)

      puts " done" if @show_progress
    rescue StandardError => e
      puts " failed (#{e.message})" if @show_progress
      # Non-fatal: continue without cache
    end

    def load_index
      return unless File.exist?(@index_path)

      # Handle both .bz2 and plain text index files
      if @index_path.end_with?(".bz2")
        require "open3"
        IO.popen(["bzcat", @index_path], "r") do |io|
          parse_index_stream(io)
        end
      else
        File.open(@index_path, "r") do |io|
          parse_index_stream(io)
        end
      end
    end

    def parse_index_stream(io)
      count = 0
      io.each_line do |line|
        line = line.strip
        next if line.empty?

        parts = line.split(":", 3)
        next if parts.size < 3

        offset = parts[0].to_i
        page_id = parts[1].to_i
        title = parts[2]

        entry = { offset: offset, page_id: page_id, title: title }
        @entries_by_title[title] = entry
        @entries_by_id[page_id] = entry

        if @stream_offsets.empty? || @stream_offsets.last != offset
          @stream_offsets << offset
        end

        # Early termination: check if we found all target titles
        if @target_titles
          @found_targets << title if @target_titles.include?(title)
          if @found_targets.size == @target_titles.size
            @early_terminated = true
            print "\r  Found all #{@target_titles.size} target articles" if @show_progress
            puts if @show_progress
            break
          end
        end

        count += 1
        if @show_progress && count % INDEX_PROGRESS_THRESHOLD == 0
          print "\r  Parsed #{count / 1_000_000.0}M entries..."
          $stdout.flush
        end
      end
      print "\r" + " " * 40 + "\r" if @show_progress && count >= INDEX_PROGRESS_THRESHOLD && !@early_terminated
    end
  end

  # Reads articles from multistream bz2 files
  class MultistreamReader
    attr_reader :multistream_path, :index

    # Initialize reader with multistream file and index
    # @param multistream_path [String] Path to the multistream bz2 file
    # @param index_or_path [MultistreamIndex, String] Either an existing index instance or path to index file
    # @param use_cache [Boolean] Whether to use SQLite cache for index (default: true, only used if index_or_path is a path)
    # @param cache_dir [String, nil] Directory for SQLite cache (only used if index_or_path is a path)
    def initialize(multistream_path, index_or_path, use_cache: true, cache_dir: nil)
      @multistream_path = multistream_path

      # Accept either an existing index or a path to create one
      if index_or_path.is_a?(MultistreamIndex)
        @index = index_or_path
      else
        @index = MultistreamIndex.new(index_or_path, use_cache: use_cache, cache_dir: cache_dir)
      end
    end

    # Extract a single article by title
    def extract_article(title)
      entry = @index.find_by_title(title)
      return nil unless entry

      stream_content = read_stream_at(entry[:offset])
      extract_page_from_xml(stream_content, title)
    end

    # Extract multiple articles (sequential)
    def extract_articles(titles)
      # Group by stream offset for efficiency
      grouped = titles.group_by { |t| @index.stream_offset_for(t) }

      results = {}
      grouped.each do |offset, titles_in_stream|
        next unless offset

        stream_content = read_stream_at(offset)
        titles_in_stream.each do |title|
          page = extract_page_from_xml(stream_content, title)
          results[title] = page if page
        end
      end
      results
    end

    # Extract multiple articles in parallel (by stream)
    # @param titles [Array<String>] Article titles to extract
    # @param num_processes [Integer] Number of parallel processes (default: 4)
    # @param progress_callback [Proc, nil] Optional callback for progress updates
    # @return [Hash] Map of title => page data
    def extract_articles_parallel(titles, num_processes: 4, &progress_callback)
      # Group titles by stream offset
      grouped = titles.group_by { |t| @index.stream_offset_for(t) }
      grouped.delete(nil) # Remove titles not found in index

      # Process streams in parallel
      stream_results = Parallel.map(grouped.keys, in_processes: num_processes) do |offset|
        titles_in_stream = grouped[offset]
        stream_content = read_stream_at(offset)

        stream_pages = {}
        titles_in_stream.each do |title|
          page = extract_page_from_xml(stream_content, title)
          stream_pages[title] = page if page
        end

        stream_pages
      end

      # Merge results from all streams
      results = {}
      stream_results.each do |stream_pages|
        results.merge!(stream_pages)
      end

      results
    end

    # Iterate through articles in parallel, yielding each page
    # Groups articles by stream and processes streams in parallel
    # @param entries [Array<Hash>] Array of index entries with :title and :offset
    # @param num_processes [Integer] Number of parallel processes
    # @yield [Hash] Page data for each article
    def each_article_parallel(entries, num_processes: 4)
      return enum_for(:each_article_parallel, entries, num_processes: num_processes) unless block_given?

      # Group by stream offset
      grouped = entries.group_by { |e| e[:offset] }

      # Process streams in parallel, collecting all pages
      all_pages = Parallel.flat_map(grouped.keys, in_processes: num_processes) do |offset|
        entries_in_stream = grouped[offset]
        stream_content = read_stream_at(offset)

        pages = []
        entries_in_stream.each do |entry|
          page = extract_page_from_xml(stream_content, entry[:title])
          pages << page if page
        end

        pages
      end

      # Yield each page (sequential, as yielding must happen in main process)
      all_pages.each { |page| yield page }
    end

    # Iterate through all articles in a stream
    def each_article_in_stream(offset, &block)
      stream_content = read_stream_at(offset)
      extract_all_pages_from_xml(stream_content, &block)
    end

    # Iterate through first N streams
    def each_article_in_first_streams(stream_count, &block)
      @index.stream_offsets.first(stream_count).each do |offset|
        each_article_in_stream(offset, &block)
      end
    end

    private

    def read_stream_at(offset)
      # Read the bz2 stream starting at the given offset
      # We need to find where this stream ends (next stream start or EOF)
      next_offset = find_next_offset(offset)

      File.open(@multistream_path, "rb") do |f|
        f.seek(offset)

        if next_offset
          compressed_data = f.read(next_offset - offset)
        else
          # Last stream - read to end
          compressed_data = f.read
        end

        decompress_bz2(compressed_data)
      end
    end

    def find_next_offset(current_offset)
      idx = @index.stream_offsets.index(current_offset)
      return nil unless idx

      @index.stream_offsets[idx + 1]
    end

    def decompress_bz2(data)
      require "stringio"
      require "open3"

      stdout, status = Open3.capture2("bzcat", stdin_data: data)
      stdout
    end

    def extract_page_from_xml(xml_content, title)
      # Simple extraction - find the page with matching title
      require "nokogiri"

      doc = Nokogiri::XML("<root>#{xml_content}</root>")
      doc.xpath("//page").each do |page_node|
        page_title = page_node.at_xpath("title")&.text
        if page_title == title
          return {
            title: page_title,
            id: page_node.at_xpath("id")&.text&.to_i,
            text: page_node.at_xpath(".//text")&.text || ""
          }
        end
      end
      nil
    end

    def extract_all_pages_from_xml(xml_content, &block)
      require "nokogiri"

      doc = Nokogiri::XML("<root>#{xml_content}</root>")
      doc.xpath("//page").each do |page_node|
        page = {
          title: page_node.at_xpath("title")&.text,
          id: page_node.at_xpath("id")&.text&.to_i,
          text: page_node.at_xpath(".//text")&.text || ""
        }
        yield page if page[:title]
      end
    end
  end

  # Manages downloading and caching of dump files
  # Supports any Wikipedia language code (e.g., en, ja, de, fr, zh, ar, etc.)
  # Language metadata is stored in lib/wp2txt/data/language_metadata.json
  class DumpManager
    DUMP_BASE_URL = "https://dumps.wikimedia.org"
    DEFAULT_CACHE_DIR = File.expand_path("~/.wp2txt/cache")

    # Legacy constant for backward compatibility
    CACHE_DIR = "tmp/dump_cache"

    attr_reader :lang, :cache_dir, :dump_expiry_days

    class << self
      # Get default cache directory
      def default_cache_dir
        DEFAULT_CACHE_DIR
      end
    end

    def initialize(lang, cache_dir: nil, dump_expiry_days: nil)
      @lang = lang.to_sym
      @cache_dir = cache_dir || DEFAULT_CACHE_DIR
      @dump_expiry_days = dump_expiry_days || Wp2txt::DEFAULT_DUMP_EXPIRY_DAYS
      FileUtils.mkdir_p(@cache_dir)
    end

    # Format bytes as human-readable string
    def format_size(bytes)
      Wp2txt.format_file_size(bytes)
    end

    # Get the latest dump date for a language
    def latest_dump_date
      @latest_dump_date ||= fetch_latest_dump_date
    end

    # Download multistream index file
    def download_index(force: false)
      index_path = cached_index_path
      if File.exist?(index_path) && !force
        puts "Index already cached: #{File.basename(index_path)}"
        $stdout.flush
        return index_path
      end

      url = index_url
      puts "Downloading index: #{url}"
      $stdout.flush
      download_file(url, index_path)
      index_path
    end

    # Download multistream dump file
    # @param force [Boolean] Force re-download even if cached
    # @param max_streams [Integer, nil] If set, only download first N streams (partial download)
    def download_multistream(force: false, max_streams: nil)
      # For partial downloads, first check if full dump exists (most efficient)
      if max_streams && !force
        full_path = cached_multistream_path
        if File.exist?(full_path)
          puts "Using cached full dump: #{File.basename(full_path)}"
          $stdout.flush
          return full_path
        end

        # Check if a larger partial download exists
        existing_partial = find_suitable_partial_cache(max_streams)
        if existing_partial
          puts "Using cached partial: #{File.basename(existing_partial)}"
          $stdout.flush
          return existing_partial
        end
      end

      dump_path = max_streams ? cached_partial_multistream_path(max_streams) : cached_multistream_path
      if File.exist?(dump_path) && !force
        puts "Multistream already cached: #{File.basename(dump_path)}"
        $stdout.flush
        return dump_path
      end

      url = multistream_url

      if max_streams
        # Partial download: need index first to know byte range
        index_path = download_index
        index = MultistreamIndex.new(index_path, cache_dir: @cache_dir)

        if index.stream_offsets.size >= max_streams
          # Get byte range for first N streams
          end_offset = index.stream_offsets[max_streams]
          puts "Downloading first #{max_streams} streams (#{format_size(end_offset)}): #{url}"
          $stdout.flush
          download_file_range(url, dump_path, 0, end_offset - 1)
        else
          puts "Only #{index.stream_offsets.size} streams available, downloading all"
          $stdout.flush
          download_file(url, dump_path)
        end
      else
        puts "Downloading multistream: #{url}"
        $stdout.flush
        download_file(url, dump_path)
      end

      dump_path
    end

    # Find a suitable cached partial download (same or larger than needed)
    # @param min_streams [Integer] Minimum number of streams needed
    # @return [String, nil] Path to suitable cached file, or nil
    def find_suitable_partial_cache(min_streams)
      pattern = File.join(@cache_dir, "#{@lang}wiki-#{latest_dump_date}-multistream-*streams.xml.bz2")
      Dir.glob(pattern).each do |path|
        if path =~ /multistream-(\d+)streams\.xml\.bz2$/
          stream_count = $1.to_i
          return path if stream_count >= min_streams
        end
      end
      nil
    end

    # Find any existing partial dump (any date)
    # @return [Hash, nil] Info about existing partial dump, or nil
    def find_any_partial_cache
      pattern = File.join(@cache_dir, "#{@lang}wiki-*-multistream-*streams.xml.bz2")
      partials = []

      Dir.glob(pattern).each do |path|
        if path =~ /#{@lang}wiki-(\d{8})-multistream-(\d+)streams\.xml\.bz2$/
          dump_date = $1
          stream_count = $2.to_i
          partials << {
            path: path,
            dump_date: dump_date,
            stream_count: stream_count,
            size: File.size(path),
            mtime: File.mtime(path)
          }
        end
      end

      # Return the largest partial (by stream count)
      partials.max_by { |p| p[:stream_count] }
    end

    # Check if incremental download is possible from existing partial
    # @param partial_info [Hash] Info from find_any_partial_cache
    # @return [Hash] Result with :possible, :reason, and details
    def can_resume_from_partial?(partial_info)
      return { possible: false, reason: :no_partial } unless partial_info

      current_date = latest_dump_date

      # Check if dump dates match
      if partial_info[:dump_date] != current_date
        return {
          possible: false,
          reason: :date_mismatch,
          partial_date: partial_info[:dump_date],
          latest_date: current_date
        }
      end

      # Validate the partial file with Bz2Validator
      require_relative "bz2_validator"
      validation = Bz2Validator.validate_quick(partial_info[:path])
      unless validation.valid?
        return {
          possible: false,
          reason: :invalid_partial,
          error: validation.message
        }
      end

      # Verify file size matches expected offset
      index_path = download_index
      index = MultistreamIndex.new(index_path, cache_dir: @cache_dir)

      expected_size = if partial_info[:stream_count] < index.stream_offsets.size
                        index.stream_offsets[partial_info[:stream_count]]
                      else
                        # Partial has all streams - no need to resume
                        return { possible: false, reason: :already_complete }
                      end

      actual_size = partial_info[:size]
      if actual_size != expected_size
        return {
          possible: false,
          reason: :size_mismatch,
          expected: expected_size,
          actual: actual_size
        }
      end

      {
        possible: true,
        partial_info: partial_info,
        current_streams: partial_info[:stream_count],
        total_streams: index.stream_offsets.size,
        current_size: actual_size
      }
    end

    # Download full dump with incremental support
    # @param force [Boolean] Force re-download
    # @param interactive [Boolean] Prompt user for choices (default: true)
    # @return [String] Path to downloaded file
    def download_multistream_full(force: false, interactive: true)
      full_path = cached_multistream_path

      # If full dump exists, use it
      if File.exist?(full_path) && !force
        puts "Using cached full dump: #{File.basename(full_path)}"
        $stdout.flush
        return full_path
      end

      # Check for existing partial dump
      partial = find_any_partial_cache
      if partial && interactive
        resume_info = can_resume_from_partial?(partial)

        if resume_info[:possible]
          # Same date - can resume
          return handle_resumable_partial(partial, resume_info, force)
        elsif resume_info[:reason] == :date_mismatch
          # Different date - ask user
          return handle_outdated_partial(partial, resume_info, force)
        elsif resume_info[:reason] == :size_mismatch || resume_info[:reason] == :invalid_partial
          # Corrupted partial - inform and re-download
          puts "Warning: Existing partial dump appears corrupted."
          puts "  Reason: #{resume_info[:reason]}"
          puts "  Will download fresh copy."
          FileUtils.rm_f(partial[:path])
        end
      end

      # Standard full download
      download_multistream(force: force, max_streams: nil)
    end

    private

    def handle_resumable_partial(partial, resume_info, force)
      current = resume_info[:current_streams]
      total = resume_info[:total_streams]
      current_size = resume_info[:current_size]

      # Calculate remaining download size
      index_path = cached_index_path
      index = MultistreamIndex.new(index_path, cache_dir: @cache_dir)

      # Get total file size from HTTP HEAD request
      url = multistream_url
      total_size = get_remote_file_size(url)
      remaining_size = total_size - current_size

      puts
      puts "Found existing partial dump (same date):"
      puts "  Current: #{current} streams (#{format_size(current_size)})"
      puts "  Total:   #{total} streams (#{format_size(total_size)})"
      puts "  Remaining: #{format_size(remaining_size)}"
      puts

      print "Download remaining data? [Y/n/f(ull fresh download)]: "
      $stdout.flush
      response = $stdin.gets&.strip&.downcase || "y"

      case response
      when "n", "no"
        puts "Using existing partial dump."
        partial[:path]
      when "f", "full", "fresh"
        puts "Downloading fresh full dump..."
        FileUtils.rm_f(partial[:path])
        download_multistream(force: true, max_streams: nil)
      else
        # Resume download
        puts "Resuming download..."
        download_incremental(partial[:path], current_size, total_size)
      end
    end

    def handle_outdated_partial(partial, resume_info, force)
      puts
      puts "Found existing partial dump with different date:"
      puts "  Partial dump: #{partial[:dump_date]} (#{partial[:stream_count]} streams, #{format_size(partial[:size])})"
      puts "  Latest dump:  #{resume_info[:latest_date]}"
      puts
      puts "Options:"
      puts "  [D] Delete old partial and download latest full dump (recommended)"
      puts "  [K] Keep old partial, download latest full dump separately"
      puts "  [U] Use old partial as-is (may have outdated content)"
      puts

      print "Choice [D/k/u]: "
      $stdout.flush
      response = $stdin.gets&.strip&.downcase || "d"

      case response
      when "k", "keep"
        puts "Keeping old partial, downloading latest full dump..."
        download_multistream(force: true, max_streams: nil)
      when "u", "use"
        puts "Using old partial dump (content may be outdated)."
        partial[:path]
      else
        puts "Deleting old partial and downloading latest..."
        FileUtils.rm_f(partial[:path])
        download_multistream(force: true, max_streams: nil)
      end
    end

    def download_incremental(partial_path, start_byte, total_size)
      url = multistream_url
      full_path = cached_multistream_path

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = DEFAULT_HTTP_TIMEOUT
      http.read_timeout = DEFAULT_HTTP_TIMEOUT
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      request = Net::HTTP::Get.new(uri)
      request["Range"] = "bytes=#{start_byte}-"

      # Copy partial to full path first, then append
      FileUtils.cp(partial_path, full_path)

      File.open(full_path, "ab") do |file|
        http.request(request) do |response|
          if response.code == "206"
            remaining = total_size - start_byte
            downloaded = 0

            response.read_body do |chunk|
              file.write(chunk)
              downloaded += chunk.size
              total_downloaded = start_byte + downloaded
              percent = (total_downloaded * 100.0 / total_size).round(1)
              print "\r  Progress: #{percent}% (#{format_size(total_downloaded)} / #{format_size(total_size)})"
              $stdout.flush
            end
            puts
          elsif response.code == "200"
            # Server doesn't support Range - need full download
            puts "\nServer doesn't support resume. Downloading full file..."
            file.close
            FileUtils.rm_f(full_path)
            return download_multistream(force: true, max_streams: nil)
          else
            raise "Download failed: #{response.code} #{response.message}"
          end
        end
      end

      # Validate the combined file
      require_relative "bz2_validator"
      validation = Bz2Validator.validate_quick(full_path)
      unless validation.valid?
        puts "Warning: Combined file validation failed. Re-downloading..."
        FileUtils.rm_f(full_path)
        return download_multistream(force: true, max_streams: nil)
      end

      puts "Successfully resumed download!"

      # Optionally remove the partial file
      FileUtils.rm_f(partial_path) if partial_path != full_path

      full_path
    end

    def get_remote_file_size(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = DEFAULT_HTTP_TIMEOUT
      http.read_timeout = DEFAULT_HTTP_TIMEOUT
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      request = Net::HTTP::Head.new(uri)
      response = http.request(request)

      response["Content-Length"]&.to_i || 0
    end

    public

    # Path for partial multistream cache
    def cached_partial_multistream_path(stream_count)
      File.join(@cache_dir, "#{@lang}wiki-#{latest_dump_date}-multistream-#{stream_count}streams.xml.bz2")
    end

    # Get paths for cached files
    def cached_index_path
      File.join(@cache_dir, "#{@lang}wiki-#{latest_dump_date}-multistream-index.txt.bz2")
    end

    def cached_multistream_path
      File.join(@cache_dir, "#{@lang}wiki-#{latest_dump_date}-multistream.xml.bz2")
    end

    # Check if cache is fresh (within configured days)
    def cache_fresh?(days = nil)
      days ||= @dump_expiry_days
      Wp2txt.file_fresh?(cached_index_path, days)
    end

    # Check if cache is stale (beyond configured expiry days)
    def cache_stale?
      !cache_fresh?
    end

    # Get cache age in days
    # Returns nil if no cache exists
    def cache_age_days
      Wp2txt.file_age_days(cached_index_path)
    end

    # Get cache modification time
    # Returns nil if no cache exists
    def cache_mtime
      path = cached_index_path
      return nil unless File.exist?(path)

      File.mtime(path)
    end

    # Get cache status information
    def cache_status
      {
        lang: @lang,
        cache_dir: @cache_dir,
        index_exists: File.exist?(cached_index_path),
        index_path: cached_index_path,
        index_size: File.exist?(cached_index_path) ? File.size(cached_index_path) : 0,
        multistream_exists: File.exist?(cached_multistream_path),
        multistream_path: cached_multistream_path,
        multistream_size: File.exist?(cached_multistream_path) ? File.size(cached_multistream_path) : 0,
        dump_date: (latest_dump_date rescue nil),
        fresh: cache_fresh?,
        age_days: cache_age_days,
        mtime: cache_mtime,
        expiry_days: @dump_expiry_days
      }
    end

    # Clear cache for this language
    def clear_cache!
      lang_dir = File.join(@cache_dir, "#{@lang}wiki")
      FileUtils.rm_rf(lang_dir) if File.exist?(lang_dir)
    end

    # Clear all cache
    def self.clear_all_cache!(cache_dir = DEFAULT_CACHE_DIR)
      FileUtils.rm_rf(cache_dir) if File.exist?(cache_dir)
    end

    # Get status for all cached languages
    def self.all_cache_status(cache_dir = DEFAULT_CACHE_DIR)
      return {} unless File.exist?(cache_dir)

      status = {}
      Dir.glob(File.join(cache_dir, "*wiki")).each do |lang_dir|
        lang = File.basename(lang_dir).sub(/wiki$/, "").to_sym
        manager = new(lang, cache_dir: cache_dir)
        status[lang] = manager.cache_status
      rescue IOError, Errno::ENOENT, Errno::EACCES, JSON::ParserError => e
        status[lang] = { error: e.message }
      end
      status
    end

    private

    def fetch_latest_dump_date
      # Try to find the latest available dump
      wiki = "#{@lang}wiki"
      uri = URI("#{DUMP_BASE_URL}/#{wiki}/")

      response = Wp2txt.ssl_safe_get(uri)
      raise("Failed to fetch dump list for #{wiki}") unless response.is_a?(Net::HTTPSuccess)

      # Find dates in format YYYYMMDD
      dates = response.body.scan(/href="(\d{8})\/"/).flatten
      dates.sort.last || raise("No dumps found for #{wiki}")
    end

    def index_url
      wiki = "#{@lang}wiki"
      date = latest_dump_date
      "#{DUMP_BASE_URL}/#{wiki}/#{date}/#{wiki}-#{date}-pages-articles-multistream-index.txt.bz2"
    end

    def multistream_url
      wiki = "#{@lang}wiki"
      date = latest_dump_date
      "#{DUMP_BASE_URL}/#{wiki}/#{date}/#{wiki}-#{date}-pages-articles-multistream.xml.bz2"
    end

    # Download metadata file path for tracking resumable downloads
    def download_meta_path(path)
      "#{path}.wp2txt_download"
    end

    # Get remote file info via HEAD request
    # @return [Hash] { size:, etag:, last_modified: }
    def get_remote_file_info(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = DEFAULT_HTTP_TIMEOUT
      http.read_timeout = DEFAULT_HTTP_TIMEOUT
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      request = Net::HTTP::Head.new(uri)
      response = http.request(request)

      {
        size: response["Content-Length"]&.to_i || 0,
        etag: response["ETag"],
        last_modified: response["Last-Modified"],
        accept_ranges: response["Accept-Ranges"] == "bytes"
      }
    end

    # Save download metadata for resume support
    def save_download_meta(path, url, remote_info)
      meta = {
        url: url,
        size: remote_info[:size],
        etag: remote_info[:etag],
        last_modified: remote_info[:last_modified],
        started_at: Time.now.iso8601
      }
      File.write(download_meta_path(path), JSON.pretty_generate(meta))
    end

    # Load download metadata
    # @return [Hash, nil] Metadata or nil if not found/invalid
    def load_download_meta(path)
      meta_path = download_meta_path(path)
      return nil unless File.exist?(meta_path)

      JSON.parse(File.read(meta_path), symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    # Clean up download metadata
    def cleanup_download_meta(path)
      FileUtils.rm_f(download_meta_path(path))
    end

    # Check if resume is safe (server file hasn't changed)
    def can_resume_download?(path, url)
      return false unless File.exist?(path)

      meta = load_download_meta(path)
      return false unless meta

      # Check if metadata is not too old (max 7 days)
      if meta[:started_at]
        started = Time.parse(meta[:started_at]) rescue nil
        if started && (Time.now - started) > days_to_seconds(RESUME_METADATA_MAX_AGE_DAYS)
          puts "  Partial download is too old (>#{RESUME_METADATA_MAX_AGE_DAYS} days). Starting fresh."
          return false
        end
      end

      # Get current remote file info
      remote_info = get_remote_file_info(url)

      # Check if ETag matches (most reliable)
      if meta[:etag] && remote_info[:etag]
        if meta[:etag] != remote_info[:etag]
          puts "  Server file has changed (ETag mismatch). Starting fresh."
          return false
        end
      # Fallback: check Last-Modified
      elsif meta[:last_modified] && remote_info[:last_modified]
        if meta[:last_modified] != remote_info[:last_modified]
          puts "  Server file has changed (Last-Modified mismatch). Starting fresh."
          return false
        end
      end

      # Check if server supports Range requests
      unless remote_info[:accept_ranges]
        puts "  Server doesn't support resume. Starting fresh."
        return false
      end

      true
    end

    def download_file(url, path)
      uri = URI(url)
      FileUtils.mkdir_p(File.dirname(path))

      # Check for resumable download
      partial_size = File.exist?(path) ? File.size(path) : 0
      resume_mode = false

      if partial_size > 0 && can_resume_download?(path, url)
        meta = load_download_meta(path)
        total_size = meta[:size]
        if partial_size < total_size
          resume_mode = true
          puts "  Resuming download from #{format_size(partial_size)} / #{format_size(total_size)} (#{(partial_size * 100.0 / total_size).round(1)}%)"
        elsif partial_size == total_size
          puts "  Download already complete."
          cleanup_download_meta(path)
          return path
        else
          # Partial is larger than expected - corrupted, start fresh
          puts "  Partial file corrupted (size mismatch). Starting fresh."
          FileUtils.rm_f(path)
          partial_size = 0
        end
      elsif partial_size > 0
        # Can't resume - remove partial and start fresh
        FileUtils.rm_f(path)
        cleanup_download_meta(path)
        partial_size = 0
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = DEFAULT_HTTP_TIMEOUT
      http.read_timeout = DEFAULT_HTTP_TIMEOUT
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      request = Net::HTTP::Get.new(uri)

      if resume_mode
        request["Range"] = "bytes=#{partial_size}-"
        file_mode = "ab"  # Append mode
      else
        file_mode = "wb"  # Write mode (overwrite)
        # Save metadata for potential future resume
        remote_info = get_remote_file_info(url)
        save_download_meta(path, url, remote_info) if remote_info[:size] > 0
      end

      File.open(path, file_mode) do |file|
        http.request(request) do |response|
          if response.code == "200" || response.code == "206"
            total = if resume_mode
                      load_download_meta(path)[:size]
                    else
                      response["Content-Length"]&.to_i
                    end
            downloaded = partial_size

            response.read_body do |chunk|
              file.write(chunk)
              downloaded += chunk.size
              if total && total > 0
                percent = (downloaded * 100.0 / total).round(1)
                print "\r  Progress: #{percent}% (#{format_size(downloaded)} / #{format_size(total)})"
                $stdout.flush
              end
            end
            puts
          elsif response.code == "416"
            # Range Not Satisfiable - file might be complete or corrupted
            puts "\n  Range error. Verifying file..."
            remote_info = get_remote_file_info(url)
            if File.size(path) == remote_info[:size]
              puts "  File is already complete."
            else
              puts "  File corrupted. Re-downloading..."
              file.close
              FileUtils.rm_f(path)
              cleanup_download_meta(path)
              return download_file(url, path)
            end
          else
            raise "Download failed: #{response.code} #{response.message}"
          end
        end
      end

      # Clean up metadata on successful completion
      cleanup_download_meta(path)

      path
    end

    # Download a range of bytes from a URL using HTTP Range header
    def download_file_range(url, path, start_byte, end_byte)
      uri = URI(url)

      FileUtils.mkdir_p(File.dirname(path))

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = DEFAULT_HTTP_TIMEOUT
      http.read_timeout = DEFAULT_HTTP_TIMEOUT
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      request = Net::HTTP::Get.new(uri)
      request["Range"] = "bytes=#{start_byte}-#{end_byte}"

      File.open(path, "wb") do |file|
        http.request(request) do |response|
          if response.code == "206" || response.code == "200"
            total = end_byte - start_byte + 1
            downloaded = 0

            response.read_body do |chunk|
              file.write(chunk)
              downloaded += chunk.size
              percent = (downloaded * 100.0 / total).round(1)
              print "\r  Progress: #{percent}% (#{format_size(downloaded)} / #{format_size(total)})"
              $stdout.flush
            end
            puts
          else
            raise "Download failed: #{response.code} #{response.message}"
          end
        end
      end

      path
    end
  end

  # Fetches category members from Wikipedia API
  # Uses SQLite-based CategoryCache for efficient repeated access
  class CategoryFetcher
    API_ENDPOINT = "https://%s.wikipedia.org/w/api.php"
    MAX_LIMIT = 500
    RATE_LIMIT_DELAY = 0.1

    attr_reader :lang, :category, :max_depth, :cache_expiry_days

    def initialize(lang, category, max_depth: 0, cache_expiry_days: nil, cache_dir: nil)
      @lang = lang.to_s
      @category = normalize_category_name(category)
      @max_depth = max_depth
      @cache_expiry_days = cache_expiry_days || Wp2txt::DEFAULT_CATEGORY_CACHE_EXPIRY_DAYS
      @cache_dir = cache_dir
      @cache = nil
      @visited_categories = Set.new
    end

    # Enable caching of category member lists
    # @param cache_dir [String] Directory for cache files
    def enable_cache(cache_dir)
      @cache_dir = cache_dir
      @cache = CategoryCache.new(@lang, cache_dir: cache_dir, expiry_days: @cache_expiry_days)
    end

    # Get the category cache instance
    # Creates one if caching is enabled but cache not yet initialized
    def cache
      return @cache if @cache
      return nil unless @cache_dir

      @cache = CategoryCache.new(@lang, cache_dir: @cache_dir, expiry_days: @cache_expiry_days)
    end

    # Preview mode - returns statistics without full article list
    def fetch_preview
      @visited_categories = Set.new
      subcategories = []
      total_articles = 0

      fetch_category_stats(@category, 0, subcategories)

      total_articles = subcategories.sum { |s| s[:article_count] }

      {
        category: @category,
        depth: @max_depth,
        subcategories: subcategories,
        total_subcategories: subcategories.size - 1,
        total_articles: total_articles
      }
    end

    # Fetch all article titles in the category (and subcategories if depth > 0)
    def fetch_articles
      @visited_categories = Set.new
      @articles = []
      fetch_category_members(@category, 0)
      @articles.uniq
    end

    private

    def normalize_category_name(name)
      name.to_s.sub(/^[Cc]ategory:/, "").strip
    end

    def fetch_category_stats(category_name, current_depth, results)
      return if @visited_categories.include?(category_name)
      @visited_categories << category_name

      cached = load_from_cache(category_name)
      if cached
        results << { name: category_name, article_count: (cached[:pages] || []).size }
        if current_depth < @max_depth
          (cached[:subcats] || []).each do |subcat|
            fetch_category_stats(subcat, current_depth + 1, results)
          end
        end
        return
      end

      pages = []
      subcats = []
      continue_token = nil

      loop do
        response = api_request(category_name, continue_token)
        break unless response

        categorymembers = response.dig("query", "categorymembers") || []
        categorymembers.each do |member|
          case member["ns"]
          when 0
            pages << member["title"]
          when 14
            subcats << member["title"].sub(/^Category:/, "")
          end
        end

        continue_token = response.dig("continue", "cmcontinue")
        break unless continue_token

        sleep(RATE_LIMIT_DELAY)
      end

      save_to_cache(category_name, { pages: pages, subcats: subcats })

      results << { name: category_name, article_count: pages.size }

      if current_depth < @max_depth
        subcats.each do |subcat|
          fetch_category_stats(subcat, current_depth + 1, results)
        end
      end
    end

    def fetch_category_members(category_name, current_depth)
      return if @visited_categories.include?(category_name)
      @visited_categories << category_name

      cached = load_from_cache(category_name)
      if cached
        @articles.concat(cached[:pages] || [])
        if current_depth < @max_depth
          (cached[:subcats] || []).each do |subcat|
            fetch_category_members(subcat, current_depth + 1)
          end
        end
        return
      end

      pages = []
      subcats = []
      continue_token = nil

      loop do
        response = api_request(category_name, continue_token)
        break unless response

        categorymembers = response.dig("query", "categorymembers") || []
        categorymembers.each do |member|
          case member["ns"]
          when 0
            pages << member["title"]
          when 14
            subcats << member["title"].sub(/^Category:/, "")
          end
        end

        continue_token = response.dig("continue", "cmcontinue")
        break unless continue_token

        sleep(RATE_LIMIT_DELAY)
      end

      save_to_cache(category_name, { pages: pages, subcats: subcats })

      @articles.concat(pages)

      if current_depth < @max_depth
        subcats.each do |subcat|
          fetch_category_members(subcat, current_depth + 1)
        end
      end
    end

    def api_request(category_name, continue_token = nil)
      uri = URI(format(API_ENDPOINT, @lang))
      params = {
        action: "query",
        list: "categorymembers",
        cmtitle: "Category:#{category_name}",
        cmtype: "page|subcat",
        cmlimit: MAX_LIMIT,
        format: "json"
      }
      params[:cmcontinue] = continue_token if continue_token
      uri.query = URI.encode_www_form(params)

      attempts = 0
      begin
        attempts += 1
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = DEFAULT_HTTP_TIMEOUT
        http.read_timeout = DEFAULT_HTTP_TIMEOUT
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER

        request = Net::HTTP::Get.new(uri)
        response = http.request(request)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET,
             Errno::ECONNREFUSED, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError => e
        if attempts <= MAX_HTTP_RETRIES
          delay = 2**attempts
          warn "  API request failed (attempt #{attempts}/#{MAX_HTTP_RETRIES + 1}): #{e.message}. Retrying in #{delay}s..."
          sleep delay
          retry
        end
        warn "  API request failed after #{attempts} attempts for category '#{category_name}': #{e.message}"
        nil
      rescue JSON::ParserError => e
        warn "  Invalid JSON response for category '#{category_name}': #{e.message}"
        nil
      end
    end

    def load_from_cache(category_name)
      return nil unless cache

      cache.get(category_name)
    end

    def save_to_cache(category_name, members)
      return unless cache

      pages = members[:pages] || members["pages"] || []
      subcats = members[:subcats] || members["subcats"] || []
      cache.save(category_name, pages, subcats)
    end
  end
end
