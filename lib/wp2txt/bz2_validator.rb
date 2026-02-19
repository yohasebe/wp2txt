# frozen_string_literal: true

require_relative "constants"

module Wp2txt
  # Validates bz2 files for corruption and integrity
  # Provides early detection of corrupt files before processing
  module Bz2Validator
    # Bz2 magic bytes: "BZ" followed by version ('h') and block size ('1'-'9')
    BZ2_MAGIC = "BZ".freeze
    BZ2_VERSION = "h".freeze
    BZ2_BLOCK_SIZES = ("1".."9").to_a.freeze

    # Minimum valid bz2 file size (header + minimal compressed data)
    MIN_BZ2_SIZE = 14

    # Test chunk size for decompression validation
    TEST_CHUNK_SIZE = 1_048_576 # 1 MB

    # Validation result structure
    ValidationResult = Struct.new(:valid, :error_type, :message, :details, keyword_init: true) do
      def valid?
        valid
      end

      def to_s
        valid ? "Valid bz2 file" : "Invalid: #{message}"
      end
    end

    module_function

    # Perform full validation of a bz2 file
    # @param path [String] Path to bz2 file
    # @param test_decompress [Boolean] Whether to test decompression (slower but more thorough)
    # @return [ValidationResult] Validation result
    def validate(path, test_decompress: true)
      # Check file exists
      unless File.exist?(path)
        return ValidationResult.new(
          valid: false,
          error_type: :not_found,
          message: "File not found",
          details: { path: path }
        )
      end

      # Check file size
      file_size = File.size(path)
      if file_size < MIN_BZ2_SIZE
        return ValidationResult.new(
          valid: false,
          error_type: :too_small,
          message: "File too small to be valid bz2 (#{file_size} bytes)",
          details: { size: file_size, minimum: MIN_BZ2_SIZE }
        )
      end

      # Check magic bytes
      magic_result = validate_magic_bytes(path)
      return magic_result unless magic_result.valid?

      # Test decompression if requested
      if test_decompress
        decompress_result = test_decompression(path)
        return decompress_result unless decompress_result.valid?
      end

      ValidationResult.new(
        valid: true,
        error_type: nil,
        message: "Valid bz2 file",
        details: { size: file_size, path: path }
      )
    end

    # Quick validation (magic bytes only, no decompression test)
    # @param path [String] Path to bz2 file
    # @return [ValidationResult] Validation result
    def validate_quick(path)
      validate(path, test_decompress: false)
    end

    # Validate bz2 magic bytes
    # @param path [String] Path to bz2 file
    # @return [ValidationResult] Validation result
    def validate_magic_bytes(path)
      header = File.binread(path, 4)

      # Check "BZ" signature
      unless header[0, 2] == BZ2_MAGIC
        return ValidationResult.new(
          valid: false,
          error_type: :invalid_magic,
          message: "Invalid bz2 header (expected 'BZ', got '#{header[0, 2].inspect}')",
          details: { expected: BZ2_MAGIC, actual: header[0, 2] }
        )
      end

      # Check version byte ('h' for bzip2)
      unless header[2] == BZ2_VERSION
        return ValidationResult.new(
          valid: false,
          error_type: :invalid_version,
          message: "Invalid bz2 version byte (expected 'h', got '#{header[2].inspect}')",
          details: { expected: BZ2_VERSION, actual: header[2] }
        )
      end

      # Check block size byte ('1'-'9')
      unless BZ2_BLOCK_SIZES.include?(header[3])
        return ValidationResult.new(
          valid: false,
          error_type: :invalid_block_size,
          message: "Invalid bz2 block size (expected '1'-'9', got '#{header[3].inspect}')",
          details: { expected: BZ2_BLOCK_SIZES, actual: header[3] }
        )
      end

      ValidationResult.new(
        valid: true,
        error_type: nil,
        message: "Valid bz2 header",
        details: { version: header[2], block_size: header[3].to_i }
      )
    rescue IOError, Errno::ENOENT, Errno::EACCES => e
      ValidationResult.new(
        valid: false,
        error_type: :read_error,
        message: "Cannot read file: #{e.message}",
        details: { error: e.class.name }
      )
    end

    # Test decompression of first chunk
    # @param path [String] Path to bz2 file
    # @return [ValidationResult] Validation result
    def test_decompression(path)
      bzcat_cmd = find_bzip2_command
      unless bzcat_cmd
        # Skip decompression test if no command available
        return ValidationResult.new(
          valid: true,
          error_type: nil,
          message: "Skipped decompression test (no bzip2 command)",
          details: { skipped: true }
        )
      end

      # Try to decompress first chunk
      begin
        # Use head to limit output and timeout to prevent hanging on large files
        output = nil
        error = nil

        IO.popen([bzcat_cmd, "-c", "-d", path], "rb", err: [:child, :out]) do |io|
          output = io.read(TEST_CHUNK_SIZE)
        end

        exit_status = $?.exitstatus

        if exit_status != 0 && (output.nil? || output.empty?)
          return ValidationResult.new(
            valid: false,
            error_type: :decompression_failed,
            message: "Decompression failed (corrupted data or truncated file)",
            details: { exit_status: exit_status }
          )
        end

        # Check if output looks like XML (Wikipedia dumps are XML)
        if output && output.bytesize > 0
          # Simple check for XML-like content
          sample = output[0, 1000].to_s.scrub("")
          unless sample.include?("<") && sample.include?(">")
            return ValidationResult.new(
              valid: false,
              error_type: :invalid_content,
              message: "Decompressed content does not appear to be XML",
              details: { sample_size: output.bytesize }
            )
          end
        end

        ValidationResult.new(
          valid: true,
          error_type: nil,
          message: "Decompression test passed",
          details: { bytes_tested: output&.bytesize || 0 }
        )
      rescue Errno::EPIPE
        # Broken pipe is OK - we only read partial output
        ValidationResult.new(
          valid: true,
          error_type: nil,
          message: "Decompression test passed (partial read)",
          details: {}
        )
      rescue IOError, Errno::ENOENT, Errno::EACCES => e
        ValidationResult.new(
          valid: false,
          error_type: :decompression_error,
          message: "Decompression error: #{e.message}",
          details: { error: e.class.name }
        )
      end
    end

    # Find available bzip2 decompression command
    # @return [String, nil] Path to command or nil
    def find_bzip2_command
      %w[lbzip2 pbzip2 bzip2 bzcat].each do |cmd|
        path = IO.popen(["which", cmd], err: File::NULL, &:read).strip
        return path unless path.empty?
      end
      nil
    end

    # Get bz2 file information
    # @param path [String] Path to bz2 file
    # @return [Hash] File information
    def file_info(path)
      return nil unless File.exist?(path)

      header = File.binread(path, 4)
      {
        path: path,
        size: File.size(path),
        size_formatted: Wp2txt.format_file_size(File.size(path)),
        valid_header: header[0, 2] == BZ2_MAGIC,
        version: header[2],
        block_size: header[3]&.to_i,
        mtime: File.mtime(path)
      }
    rescue IOError, Errno::ENOENT, Errno::EACCES
      nil
    end
  end
end
