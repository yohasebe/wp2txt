# frozen_string_literal: true

module Wp2txt
  # =========================================================================
  # Custom Exception Classes
  # =========================================================================
  # Base error class for all Wp2txt errors
  class Error < StandardError; end

  # Raised when text parsing or conversion fails
  class ParseError < Error; end

  # Raised when network operations fail
  class NetworkError < Error; end

  # Raised when file I/O operations fail
  class FileIOError < Error; end

  # Raised when encoding conversion fails
  class EncodingError < Error; end

  # Raised when cache operations fail
  class CacheError < Error; end

  # =========================================================================
  # Shared Constants
  # =========================================================================
  # Centralized constants to avoid magic numbers and duplication across files.
  # This file should be required by all modules that need these values.

  # ---------------------------------------------------------------------------
  # Time Constants
  # ---------------------------------------------------------------------------
  SECONDS_PER_DAY = 86_400
  SECONDS_PER_HOUR = 3_600
  SECONDS_PER_MINUTE = 60

  # ---------------------------------------------------------------------------
  # Cache Settings
  # ---------------------------------------------------------------------------
  # Default expiry for downloaded Wikipedia dump files
  DEFAULT_DUMP_EXPIRY_DAYS = 30

  # Default expiry for category member cache
  DEFAULT_CATEGORY_CACHE_EXPIRY_DAYS = 7

  # Default expiry for test data cache
  DEFAULT_TEST_DATA_EXPIRY_DAYS = 30

  # ---------------------------------------------------------------------------
  # Processing Limits
  # ---------------------------------------------------------------------------
  # Safety limit for deeply nested structure processing (templates, tables, etc.)
  # This prevents infinite loops in malformed markup
  MAX_NESTING_ITERATIONS = 50_000

  # Buffer size for file reading (10 MB)
  # Optimized for Wikipedia dump processing
  DEFAULT_BUFFER_SIZE = 10_485_760

  # Minimum buffer size (1 MB) - don't go below this
  MIN_BUFFER_SIZE = 1_048_576

  # Maximum buffer size (100 MB) - don't exceed this
  MAX_BUFFER_SIZE = 104_857_600

  # ---------------------------------------------------------------------------
  # File Size Units (Binary - for accurate file sizes)
  # ---------------------------------------------------------------------------
  BYTES_PER_KB = 1_024
  BYTES_PER_MB = 1_024 * 1_024
  BYTES_PER_GB = 1_024 * 1_024 * 1_024

  # ---------------------------------------------------------------------------
  # Supported Languages
  # ---------------------------------------------------------------------------
  # Core languages for validation and testing
  # These represent major Wikipedia editions with diverse scripts and structures
  CORE_LANGUAGES = %i[en ja zh ru ar ko de fr es it pt nl pl].freeze

  # Minimum set for quick tests
  QUICK_TEST_LANGUAGES = %i[en ja].freeze

  # ---------------------------------------------------------------------------
  # Helper Methods
  # ---------------------------------------------------------------------------
  module_function

  # Convert days to seconds
  # @param days [Integer, Float] Number of days
  # @return [Integer] Seconds
  def days_to_seconds(days)
    (days * SECONDS_PER_DAY).to_i
  end

  # Check if a file is older than specified days
  # @param path [String] File path
  # @param days [Integer] Number of days
  # @return [Boolean] true if file is fresh (not expired)
  def file_fresh?(path, days)
    return false unless File.exist?(path)

    File.mtime(path) > Time.now - days_to_seconds(days)
  end

  # Calculate file age in days
  # @param path [String] File path
  # @return [Float, nil] Age in days, or nil if file doesn't exist
  def file_age_days(path)
    return nil unless File.exist?(path)

    ((Time.now - File.mtime(path)) / SECONDS_PER_DAY).round(1)
  end

  # Format file size in human-readable form (binary units)
  # @param bytes [Integer] Size in bytes
  # @return [String] Formatted size (e.g., "1.5 MB")
  def format_file_size(bytes)
    if bytes < BYTES_PER_KB
      "#{bytes} B"
    elsif bytes < BYTES_PER_MB
      "#{(bytes.to_f / BYTES_PER_KB).round(1)} KB"
    elsif bytes < BYTES_PER_GB
      "#{(bytes.to_f / BYTES_PER_MB).round(1)} MB"
    else
      "#{(bytes.to_f / BYTES_PER_GB).round(2)} GB"
    end
  end
end
