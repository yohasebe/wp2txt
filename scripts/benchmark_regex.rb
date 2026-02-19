# frozen_string_literal: true

# Benchmark script for wp2txt regex performance
# Compares pre-compiled regex patterns vs inline compilation
#
# Usage: ruby scripts/benchmark_regex.rb

require "benchmark"
begin
  require "benchmark/ips"
rescue LoadError
  # benchmark-ips is optional
end

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "wp2txt"
require "wp2txt/article"

# Sample Wikipedia-like content for benchmarking
SAMPLE_TEXT = <<~WIKI
  {{Infobox person
  | name = Test Person
  | birth_date = 1980-01-01
  | occupation = Writer
  }}
  '''Test Article''' is a [[test]] article with various [[wiki markup|markup]].

  == Section 1 ==
  This section has some {{cite web|url=http://example.com|title=Example}} references.
  There are also [[Category:Test]] links and [[File:Image.jpg|thumb|A caption]].

  === Subsection ===
  More content with '''bold''' and ''italic'' text.
  * List item 1
  * List item 2
  # Numbered item

  == Section 2 ==
  {| class="wikitable"
  |-
  ! Header 1 !! Header 2
  |-
  | Cell 1 || Cell 2
  |}

  Some text with &nbsp; entities and &#x266A; characters.
  Also has <ref name="test">Reference content</ref> and <nowiki>[[preserved]]</nowiki>.

  {{DEFAULTSORT:Test Article}}
  [[Category:Articles]]
  [[Category:Tests]]
WIKI

# Create multiple copies for more realistic benchmarking
LARGE_TEXT = (SAMPLE_TEXT * 100).freeze

class BenchmarkRunner
  include Wp2txt

  def initialize
    @nowikis = {}
  end

  def run_cleanup(text)
    cleanup(text.dup)
  end

  def run_full_format(text)
    format_wiki(text.dup)
  end
end

def run_benchmarks
  puts "=" * 60
  puts "wp2txt Regex Performance Benchmark"
  puts "=" * 60
  puts
  puts "Ruby version: #{RUBY_VERSION}"
  puts "Sample text size: #{SAMPLE_TEXT.bytesize} bytes"
  puts "Large text size: #{LARGE_TEXT.bytesize} bytes"
  puts

  runner = BenchmarkRunner.new

  puts "-" * 60
  puts "Warmup (JIT compilation, method caching)"
  puts "-" * 60
  5.times { runner.run_cleanup(SAMPLE_TEXT) }
  5.times { runner.run_full_format(SAMPLE_TEXT) }
  puts "Done."
  puts

  puts "-" * 60
  puts "Benchmark: cleanup() method"
  puts "-" * 60

  Benchmark.bm(20) do |x|
    x.report("cleanup (small):") do
      1000.times { runner.run_cleanup(SAMPLE_TEXT) }
    end

    x.report("cleanup (large):") do
      10.times { runner.run_cleanup(LARGE_TEXT) }
    end
  end

  puts
  puts "-" * 60
  puts "Benchmark: format_wiki() method (full pipeline)"
  puts "-" * 60

  Benchmark.bm(20) do |x|
    x.report("format_wiki (small):") do
      1000.times { runner.run_full_format(SAMPLE_TEXT) }
    end

    x.report("format_wiki (large):") do
      10.times { runner.run_full_format(LARGE_TEXT) }
    end
  end

  # If benchmark-ips is available, run IPS benchmarks
  if defined?(Benchmark::IPS)
    puts
    puts "-" * 60
    puts "IPS Benchmark (iterations per second)"
    puts "-" * 60

    Benchmark.ips do |x|
      x.report("cleanup") { runner.run_cleanup(SAMPLE_TEXT) }
      x.report("format_wiki") { runner.run_full_format(SAMPLE_TEXT) }
      x.compare!
    end
  end

  puts
  puts "-" * 60
  puts "Memory profile (approximate)"
  puts "-" * 60

  # Simple memory measurement
  GC.start
  before = GC.stat[:total_allocated_objects]
  100.times { runner.run_cleanup(SAMPLE_TEXT) }
  after = GC.stat[:total_allocated_objects]
  puts "cleanup() allocations per call: ~#{(after - before) / 100}"

  GC.start
  before = GC.stat[:total_allocated_objects]
  100.times { runner.run_full_format(SAMPLE_TEXT) }
  after = GC.stat[:total_allocated_objects]
  puts "format_wiki() allocations per call: ~#{(after - before) / 100}"

  puts
  puts "=" * 60
  puts "Benchmark complete"
  puts "=" * 60
end

run_benchmarks
