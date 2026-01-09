# frozen_string_literal: true

require "nokogiri"
require "stringio"
require_relative "constants"
require_relative "memory_monitor"
require_relative "bz2_validator"

module Wp2txt
  # StreamProcessor handles streaming decompression and XML parsing
  # without creating intermediate files
  class StreamProcessor
    include Wp2txt

    # Buffer size bounds from constants
    MIN_BUFFER_SIZE = Wp2txt::MIN_BUFFER_SIZE
    MAX_BUFFER_SIZE = Wp2txt::MAX_BUFFER_SIZE
    DEFAULT_BUFFER_SIZE = Wp2txt::DEFAULT_BUFFER_SIZE

    attr_reader :buffer_size, :pages_processed, :bytes_read

    def initialize(input_path, bz2_gem: false, adaptive_buffer: true, validate_bz2: true)
      @input_path = input_path
      @bz2_gem = bz2_gem
      @buffer = +""
      @file_pointer = nil
      @adaptive_buffer = adaptive_buffer
      @buffer_size = adaptive_buffer ? calculate_optimal_buffer_size : DEFAULT_BUFFER_SIZE
      @pages_processed = 0
      @bytes_read = 0
      @validate_bz2 = validate_bz2
    end

    # Validate bz2 file before processing
    # @param quick [Boolean] Use quick validation (header only) vs full validation
    # @return [Bz2Validator::ValidationResult] Validation result
    # @raise [Wp2txt::FileIOError] If validation fails and raise_on_error is true
    def validate_input(quick: false, raise_on_error: false)
      return nil unless @input_path.end_with?(".bz2")

      result = quick ? Bz2Validator.validate_quick(@input_path) : Bz2Validator.validate(@input_path)

      if !result.valid? && raise_on_error
        raise Wp2txt::FileIOError, "Invalid bz2 file: #{result.message}"
      end

      result
    end

    # Calculate optimal buffer size based on available memory
    def calculate_optimal_buffer_size
      MemoryMonitor.optimal_buffer_size
    rescue StandardError
      DEFAULT_BUFFER_SIZE
    end

    # Get current memory statistics
    def memory_stats
      MemoryMonitor.memory_stats
    end

    # Iterate over each page in the input
    # Yields [title, text] for each page
    def each_page
      return enum_for(:each_page) unless block_given?

      if File.directory?(@input_path)
        # Process XML files in directory
        Dir.glob(File.join(@input_path, "*.xml")).sort.each do |xml_file|
          process_xml_file(xml_file) { |title, text| yield title, text }
        end
      elsif @input_path.end_with?(".bz2")
        # Process bz2 compressed file with streaming
        process_bz2_stream { |title, text| yield title, text }
      elsif @input_path.end_with?(".xml")
        # Process single XML file
        process_xml_file(@input_path) { |title, text| yield title, text }
      else
        raise ArgumentError, "Unsupported input format: #{@input_path}"
      end
    end

    # Get processing statistics (public API for monitoring)
    def stats
      {
        pages_processed: @pages_processed,
        bytes_read: @bytes_read,
        buffer_size: @buffer_size,
        current_buffer_length: @buffer.bytesize,
        memory: memory_stats
      }
    end

    private

    # Process a single XML file
    def process_xml_file(xml_file)
      @buffer = +""
      @file_pointer = File.open(xml_file, "r:UTF-8")

      while (page = extract_next_page)
        result = parse_page_xml(page)
        yield result if result
      end

      @file_pointer.close
    end

    # Process bz2 stream directly without intermediate files
    def process_bz2_stream
      # Validate bz2 file before processing (if enabled)
      if @validate_bz2
        validation = validate_input(quick: false)
        unless validation.nil? || validation.valid?
          raise Wp2txt::FileIOError, "Cannot process corrupted bz2 file: #{validation.message}"
        end
      end

      @buffer = +""
      @file_pointer = open_bz2_stream

      while (page = extract_next_page)
        result = parse_page_xml(page)
        yield result if result
      end

      @file_pointer.close
    rescue Errno::EPIPE
      # Ignore broken pipe (can happen if we stop reading early)
    end

    # Open bz2 stream using external command or gem
    def open_bz2_stream
      if @bz2_gem
        require "bzip2-ruby"
        Bzip2::Reader.new(File.open(@input_path, "rb"))
      elsif Gem.win_platform?
        IO.popen(["bunzip2.exe", "-c", @input_path], "rb")
      else
        bzpath = find_bzip2_command
        raise "No bzip2 decompression command found" unless bzpath
        IO.popen([bzpath, "-c", "-d", @input_path], "rb")
      end
    end

    # Find available bzip2 command
    def find_bzip2_command
      %w[lbzip2 pbzip2 bzip2].each do |cmd|
        path = `which #{cmd} 2>/dev/null`.strip
        return path unless path.empty?
      end
      nil
    end

    # Fill buffer from file pointer
    def fill_buffer
      chunk = @file_pointer.read(@buffer_size)
      return false unless chunk

      @bytes_read += chunk.bytesize

      # Handle encoding for bz2 streams
      chunk = chunk.force_encoding("UTF-8")
      chunk = chunk.scrub("")
      @buffer << chunk

      # Adaptive buffer adjustment: if memory is low, reduce buffer size
      if @adaptive_buffer && MemoryMonitor.memory_low?
        new_size = [@buffer_size / 2, MIN_BUFFER_SIZE].max
        @buffer_size = new_size if new_size != @buffer_size
      end

      true
    end

    # Extract next <page>...</page> from buffer
    def extract_next_page
      loop do
        # Look for complete page in buffer
        start_idx = @buffer.index("<page>")
        if start_idx
          end_idx = @buffer.index("</page>", start_idx)
          if end_idx
            # Extract the complete page
            page_end = end_idx + "</page>".length
            page = @buffer[start_idx...page_end]
            @buffer = @buffer[page_end..]
            return page
          end
        end

        # Need more data
        break unless fill_buffer
      end

      # Check for remaining page in buffer (end of file)
      start_idx = @buffer.index("<page>")
      return nil unless start_idx

      end_idx = @buffer.index("</page>", start_idx)
      return nil unless end_idx

      page_end = end_idx + "</page>".length
      page = @buffer[start_idx...page_end]
      @buffer = @buffer[page_end..]
      page
    end

    # Parse page XML and extract title and text
    def parse_page_xml(page_xml)
      # Wrap in minimal mediawiki element for parsing
      xmlns = '<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.5/">'
      xml = xmlns + page_xml + "</mediawiki>"

      doc = Nokogiri::XML(xml, nil, "UTF-8")
      text_node = doc.xpath("//xmlns:text").first
      return nil unless text_node

      title_node = text_node.parent.parent.at_css("title")
      return nil unless title_node

      title = title_node.content
      # Skip special pages (containing colon in title like "Wikipedia:", "File:", etc.)
      return nil if title.include?(":")

      text = text_node.content
      # Remove HTML comments while preserving newline count
      text = text.gsub(/<!--(.*?)-->/m) do |content|
        num_newlines = content.count("\n")
        num_newlines.zero? ? "" : "\n" * num_newlines
      end

      @pages_processed += 1
      [title, text]
    rescue Nokogiri::XML::SyntaxError
      # Skip malformed XML
      nil
    end
  end
end
