# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_group "Core", "lib/wp2txt"
  minimum_coverage 20  # Temporarily lowered, will increase as we add tests
end

require "rspec"
require "stringio"

# Load wp2txt modules
require_relative "../lib/wp2txt"
require_relative "../lib/wp2txt/article"
require_relative "../lib/wp2txt/utils"
require_relative "../lib/wp2txt/regex"
require_relative "../lib/wp2txt/multistream"
require_relative "../lib/wp2txt/config"
require_relative "../lib/wp2txt/template_expander"
require_relative "../lib/wp2txt/parser_functions"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Helper to suppress stderr output during tests
  config.include Module.new {
    def suppress_stderr
      original_stderr = $stderr
      $stderr = StringIO.new
      yield
    ensure
      $stderr = original_stderr
    end

    def suppress_stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = original_stdout
    end

    def suppress_output
      original_stdout = $stdout
      original_stderr = $stderr
      $stdout = StringIO.new
      $stderr = StringIO.new
      yield
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end
  }

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = false  # Suppress warnings during test runs
  config.order = :random
  Kernel.srand config.seed
end
