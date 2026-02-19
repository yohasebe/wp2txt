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

  # ---------------------------------------------------------------------------
  # Network Settings
  # ---------------------------------------------------------------------------
  # Default timeout for HTTP requests (seconds)
  DEFAULT_HTTP_TIMEOUT = 30

  # Default progress reporting interval (seconds)
  DEFAULT_PROGRESS_INTERVAL = 10

  # Index parsing progress reporting threshold (entries)
  INDEX_PROGRESS_THRESHOLD = 500_000

  # Default number of top section headings to include in stats output
  DEFAULT_TOP_N_SECTIONS = 50

  # Download resume metadata max age (days)
  RESUME_METADATA_MAX_AGE_DAYS = 7

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
