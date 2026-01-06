# frozen_string_literal: true

require "json"
require "fileutils"

module Wp2txt
  # OutputWriter handles output file management with rotation
  # Supports both text and JSONL formats
  class OutputWriter
    # @param output_dir [String] Output directory path
    # @param base_name [String] Base name for output files
    # @param format [Symbol] Output format (:text or :json)
    # @param file_size_mb [Integer] Target file size in MB for rotation (0 = single file)
    def initialize(output_dir:, base_name:, format: :text, file_size_mb: 10)
      @output_dir = output_dir
      @base_name = base_name
      @format = format
      @file_size_mb = file_size_mb
      @file_size_bytes = file_size_mb * 1024 * 1024

      @current_file = nil
      @current_size = 0
      @file_index = 1
      @mutex = Mutex.new
      @output_files = []

      FileUtils.mkdir_p(@output_dir) unless File.directory?(@output_dir)
    end

    # Write formatted article to output
    # Thread-safe for parallel processing
    # @param content [String, Hash] Content to write (String for text, Hash for JSON)
    def write(content)
      return if content.nil? || (content.is_a?(String) && content.strip.empty?)

      @mutex.synchronize do
        ensure_file_open

        output = format_output(content)
        @current_file.write(output)
        @current_size += output.bytesize

        rotate_file_if_needed
      end
    end

    # Close current file and finalize
    def close
      @mutex.synchronize do
        close_current_file
      end
      @output_files
    end

    # Get list of output files created
    attr_reader :output_files

    private

    def ensure_file_open
      return if @current_file && !@current_file.closed?

      filename = generate_filename
      @current_file = File.open(filename, "w:UTF-8")
      @output_files << filename
      @current_size = 0
    end

    def close_current_file
      return unless @current_file && !@current_file.closed?

      @current_file.close

      # Remove empty files
      last_file = @output_files.last
      if last_file && File.exist?(last_file) && File.size(last_file).zero?
        File.delete(last_file)
        @output_files.pop
      end
    end

    def rotate_file_if_needed
      return if @file_size_bytes.zero? # No rotation if file_size is 0
      return if @current_size < @file_size_bytes

      close_current_file
      @file_index += 1
    end

    def generate_filename
      extension = @format == :json ? "jsonl" : "txt"
      if @file_size_bytes.zero?
        # Single file mode
        File.join(@output_dir, "#{@base_name}.#{extension}")
      else
        # Multiple files with index
        File.join(@output_dir, "#{@base_name}-#{@file_index}.#{extension}")
      end
    end

    def format_output(content)
      case @format
      when :json
        if content.is_a?(Hash)
          JSON.generate(content) + "\n"
        else
          content.to_s
        end
      else
        content.to_s
      end
    end
  end
end
