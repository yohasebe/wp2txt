# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "uri"
require "openssl"
require "parallel"
require_relative "constants"

module Wp2txt
  # SSL-safe HTTP helper to handle CRL verification issues in some environments
  # @param uri [URI] The URI to request
  # @param timeout [Integer] Timeout in seconds (default: 30)
  # @return [Net::HTTPResponse] The HTTP response
  def self.ssl_safe_get(uri, timeout: 30)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = timeout
    http.read_timeout = timeout

    if http.use_ssl?
      # Skip CRL verification which can fail in some bundled environments
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.verify_callback = ->(_preverify_ok, _store_ctx) { true }
    end

    request = Net::HTTP::Get.new(uri)
    http.request(request)
  end
  # Manages multistream index for random access to Wikipedia dumps
  class MultistreamIndex
    attr_reader :index_path, :entries_by_title, :entries_by_id, :stream_offsets

    def initialize(index_path)
      @index_path = index_path
      @entries_by_title = {}
      @entries_by_id = {}
      @stream_offsets = []
      load_index
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

    def load_index
      return unless File.exist?(@index_path)

      current_offset = nil

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

        count += 1
        if count % 500_000 == 0
          print "\r  Parsed #{count / 1_000_000.0}M entries..."
          $stdout.flush
        end
      end
      print "\r" + " " * 40 + "\r" if count >= 500_000  # Clear progress line
    end
  end

  # Reads articles from multistream bz2 files
  class MultistreamReader
    attr_reader :multistream_path, :index

    def initialize(multistream_path, index_path)
      @multistream_path = multistream_path
      @index = MultistreamIndex.new(index_path)
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
        index = MultistreamIndex.new(index_path)

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
      index = MultistreamIndex.new(index_path)

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
      index = MultistreamIndex.new(index_path)

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
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_callback = ->(_preverify_ok, _store_ctx) { true }
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
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_callback = ->(_preverify_ok, _store_ctx) { true }
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

    def download_file(url, path)
      uri = URI(url)

      FileUtils.mkdir_p(File.dirname(path))

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_callback = ->(_preverify_ok, _store_ctx) { true }
      end

      request = Net::HTTP::Get.new(uri)

      File.open(path, "wb") do |file|
        http.request(request) do |response|
          if response.code == "200"
            total = response["Content-Length"]&.to_i
            downloaded = 0

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
          else
            raise "Download failed: #{response.code} #{response.message}"
          end
        end
      end

      path
    end

    # Download a range of bytes from a URL using HTTP Range header
    def download_file_range(url, path, start_byte, end_byte)
      uri = URI(url)

      FileUtils.mkdir_p(File.dirname(path))

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_callback = ->(_preverify_ok, _store_ctx) { true }
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
  class CategoryFetcher
    API_ENDPOINT = "https://%s.wikipedia.org/w/api.php"
    MAX_LIMIT = 500
    RATE_LIMIT_DELAY = 0.1

    attr_reader :lang, :category, :max_depth, :cache_expiry_days

    def initialize(lang, category, max_depth: 0, cache_expiry_days: nil)
      @lang = lang.to_s
      @category = normalize_category_name(category)
      @max_depth = max_depth
      @cache_expiry_days = cache_expiry_days || Wp2txt::DEFAULT_CATEGORY_CACHE_EXPIRY_DAYS
      @cache_dir = nil
      @visited_categories = Set.new
    end

    # Enable caching of category member lists
    def enable_cache(cache_dir)
      @cache_dir = cache_dir
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

      # Use custom HTTP client to handle SSL certificate issues
      # Some environments have CRL verification issues with certain certificates
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 30
      http.read_timeout = 30
      # Skip CRL verification which can fail in some environments
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.verify_callback = ->(_preverify_ok, _store_ctx) { true }

      request = Net::HTTP::Get.new(uri)
      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, JSON::ParserError, OpenSSL::SSL::SSLError
      nil
    end

    def cache_path(category_name)
      return nil unless @cache_dir

      safe_name = category_name.gsub(/[^a-zA-Z0-9_\-]/, "_")
      File.join(@cache_dir, "category_#{@lang}_#{safe_name}.json")
    end

    def load_from_cache(category_name)
      path = cache_path(category_name)
      return nil unless path && File.exist?(path)

      # Check cache freshness using shared helper
      return nil unless Wp2txt.file_fresh?(path, @cache_expiry_days)

      data = JSON.parse(File.read(path), symbolize_names: true)
      data
    rescue IOError, Errno::ENOENT, Errno::EACCES, JSON::ParserError
      nil
    end

    def save_to_cache(category_name, members)
      path = cache_path(category_name)
      return unless path

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.generate(members))
    rescue IOError, Errno::ENOENT, Errno::EACCES, Errno::ENOSPC
      # Ignore cache write failures (disk full, permission denied, etc.)
    end
  end
end
