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

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

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
