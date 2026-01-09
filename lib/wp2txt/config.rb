# frozen_string_literal: true

require "yaml"
require "fileutils"

module Wp2txt
  # Configuration management for wp2txt
  # Loads and saves settings from ~/.wp2txt/config.yml
  class Config
    # Default configuration file path
    DEFAULT_CONFIG_PATH = File.expand_path("~/.wp2txt/config.yml")
    # Default cache directory
    DEFAULT_CACHE_DIR = File.expand_path("~/.wp2txt/cache")

    # Validation ranges
    DUMP_EXPIRY_RANGE = (1..365)
    CATEGORY_EXPIRY_RANGE = (1..90)
    DEPTH_RANGE = (0..10)
    VALID_FORMATS = %w[text json].freeze

    # Default values
    DEFAULTS = {
      dump_expiry_days: 30,
      category_expiry_days: 7,
      cache_directory: DEFAULT_CACHE_DIR,
      default_format: "text",
      default_depth: 0
    }.freeze

    attr_reader :dump_expiry_days, :category_expiry_days, :cache_directory,
                :default_format, :default_depth

    def initialize(
      dump_expiry_days: DEFAULTS[:dump_expiry_days],
      category_expiry_days: DEFAULTS[:category_expiry_days],
      cache_directory: DEFAULTS[:cache_directory],
      default_format: DEFAULTS[:default_format],
      default_depth: DEFAULTS[:default_depth]
    )
      @dump_expiry_days = clamp(dump_expiry_days.to_i, DUMP_EXPIRY_RANGE)
      @category_expiry_days = clamp(category_expiry_days.to_i, CATEGORY_EXPIRY_RANGE)
      @cache_directory = cache_directory.to_s.empty? ? DEFAULT_CACHE_DIR : cache_directory.to_s
      @default_format = validate_format(default_format.to_s)
      @default_depth = clamp(default_depth.to_i, DEPTH_RANGE)
    end

    # Load configuration from file
    # @param path [String] Path to config file (default: ~/.wp2txt/config.yml)
    # @return [Config] Configuration object
    def self.load(path = default_path)
      return new unless File.exist?(path)

      begin
        data = YAML.safe_load(File.read(path), symbolize_names: true) || {}
        from_hash(data)
      rescue Psych::SyntaxError, StandardError
        # Return defaults on parse error
        new
      end
    end

    # Create Config from hash
    # @param data [Hash] Configuration hash
    # @return [Config] Configuration object
    def self.from_hash(data)
      cache = data[:cache] || {}
      defaults = data[:defaults] || {}

      new(
        dump_expiry_days: cache[:dump_expiry_days] || DEFAULTS[:dump_expiry_days],
        category_expiry_days: cache[:category_expiry_days] || DEFAULTS[:category_expiry_days],
        cache_directory: cache[:directory] || DEFAULTS[:cache_directory],
        default_format: defaults[:format] || DEFAULTS[:default_format],
        default_depth: defaults[:depth] || DEFAULTS[:default_depth]
      )
    end

    # Default configuration file path
    # @return [String] Path to default config file
    def self.default_path
      DEFAULT_CONFIG_PATH
    end

    # Create default configuration file
    # @param path [String] Path to config file
    # @param force [Boolean] Overwrite existing file
    # @return [Boolean] True if file was created
    def self.create_default(path = default_path, force: false)
      return false if File.exist?(path) && !force

      config = new
      config.save(path)
      true
    end

    # Save configuration to file
    # @param path [String] Path to config file
    def save(path = self.class.default_path)
      FileUtils.mkdir_p(File.dirname(path))

      content = generate_yaml
      File.write(path, content)
    end

    # Convert to hash representation
    # @return [Hash] Configuration as hash
    def to_h
      {
        cache: {
          dump_expiry_days: @dump_expiry_days,
          category_expiry_days: @category_expiry_days,
          directory: @cache_directory
        },
        defaults: {
          format: @default_format,
          depth: @default_depth
        }
      }
    end

    private

    # Clamp value to range
    def clamp(value, range)
      [[value, range.min].max, range.max].min
    end

    # Validate format string
    def validate_format(format)
      VALID_FORMATS.include?(format) ? format : DEFAULTS[:default_format]
    end

    # Generate YAML content with comments
    def generate_yaml
      <<~YAML
        # WP2TXT Configuration File
        # Location: ~/.wp2txt/config.yml

        cache:
          # Number of days before dump files are considered stale (1-365)
          dump_expiry_days: #{@dump_expiry_days}

          # Number of days before category cache expires (1-90)
          category_expiry_days: #{@category_expiry_days}

          # Cache directory for downloaded dumps
          directory: #{@cache_directory}

        defaults:
          # Default output format: text or json
          format: #{@default_format}

          # Default subcategory recursion depth (0-10)
          depth: #{@default_depth}
      YAML
    end
  end
end
