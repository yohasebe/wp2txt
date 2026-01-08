# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "uri"

module Wp2txt
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

    # Extract multiple articles
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

    # Legacy language configuration (for reference only - any language code is supported)
    CORE_LANGUAGES = [:en, :ja, :zh, :ru, :ar, :ko].freeze

    attr_reader :lang, :cache_dir

    class << self
      # Get default cache directory
      def default_cache_dir
        DEFAULT_CACHE_DIR
      end
    end

    def initialize(lang, cache_dir: nil)
      @lang = lang.to_sym
      @cache_dir = cache_dir || DEFAULT_CACHE_DIR
      FileUtils.mkdir_p(@cache_dir)
    end

    # Format bytes as human-readable string (KB or MB)
    def format_size(bytes)
      if bytes < 1_000_000
        "#{(bytes / 1_000.0).round(0)}KB"
      else
        "#{(bytes / 1_000_000.0).round(1)}MB"
      end
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

    # Check if cache is fresh (within days)
    def cache_fresh?(days = 30)
      path = cached_index_path
      return false unless File.exist?(path)

      File.mtime(path) > Time.now - (days * 86400)
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
        fresh: cache_fresh?
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
      rescue StandardError => e
        status[lang] = { error: e.message }
      end
      status
    end

    private

    def fetch_latest_dump_date
      # Try to find the latest available dump
      wiki = "#{@lang}wiki"
      uri = URI("#{DUMP_BASE_URL}/#{wiki}/")

      response = Net::HTTP.get(uri)
      # Find dates in format YYYYMMDD
      dates = response.scan(/href="(\d{8})\/"/).flatten
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

      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
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
      end

      path
    end

    # Download a range of bytes from a URL using HTTP Range header
    def download_file_range(url, path, start_byte, end_byte)
      uri = URI(url)

      FileUtils.mkdir_p(File.dirname(path))

      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
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
      end

      path
    end
  end
end
