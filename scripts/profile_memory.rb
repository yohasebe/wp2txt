# frozen_string_literal: true

# Memory profiling script for wp2txt streaming operations
# Demonstrates the MemoryMonitor module and adaptive buffer sizing
#
# Usage: ruby scripts/profile_memory.rb [input_file.xml]

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "wp2txt"
require "wp2txt/memory_monitor"
require "wp2txt/stream_processor"

def print_separator(title = nil)
  puts
  puts "=" * 60
  puts title if title
  puts "=" * 60
end

def profile_memory_monitor
  print_separator("MemoryMonitor Module Test")

  puts "System Memory Information:"
  puts "-" * 40

  stats = Wp2txt::MemoryMonitor.memory_stats
  stats.each do |key, value|
    formatted_key = key.to_s.gsub("_", " ").capitalize
    puts "  #{formatted_key}: #{value}"
  end

  puts
  puts "Raw values:"
  puts "  Current usage: #{Wp2txt::MemoryMonitor.format_memory(Wp2txt::MemoryMonitor.current_memory_usage)}"
  puts "  Total system:  #{Wp2txt::MemoryMonitor.format_memory(Wp2txt::MemoryMonitor.total_system_memory)}"
  puts "  Available:     #{Wp2txt::MemoryMonitor.format_memory(Wp2txt::MemoryMonitor.available_memory)}"
  puts "  Optimal buffer: #{Wp2txt::MemoryMonitor.format_memory(Wp2txt::MemoryMonitor.optimal_buffer_size)}"
end

def profile_stream_processor(input_file)
  print_separator("StreamProcessor Memory Profile")

  unless File.exist?(input_file)
    puts "File not found: #{input_file}"
    puts "Creating a sample XML file for testing..."

    # Create a sample file for testing
    sample_xml = <<~XML
      <mediawiki>
      #{(1..100).map { |i| <<~PAGE
        <page>
          <title>Test Article #{i}</title>
          <revision>
            <text>This is test content for article #{i}. #{"Lorem ipsum " * 100}</text>
          </revision>
        </page>
        PAGE
      }.join}
      </mediawiki>
    XML

    input_file = "/tmp/wp2txt_test_sample.xml"
    File.write(input_file, sample_xml)
    puts "Created sample file: #{input_file} (#{File.size(input_file)} bytes)"
  end

  puts
  puts "Processing: #{input_file}"
  puts "File size: #{Wp2txt::MemoryMonitor.format_memory(File.size(input_file))}"
  puts

  # Test with adaptive buffer
  puts "Testing with adaptive buffer sizing:"
  puts "-" * 40

  processor = Wp2txt::StreamProcessor.new(input_file, adaptive_buffer: true)
  puts "Initial buffer size: #{Wp2txt::MemoryMonitor.format_memory(processor.buffer_size)}"

  start_time = Time.now
  start_memory = Wp2txt::MemoryMonitor.current_memory_usage

  page_count = 0
  processor.each_page do |title, _text|
    page_count += 1
    if page_count % 10 == 0
      stats = processor.stats
      puts "  Processed #{page_count} pages, buffer: #{Wp2txt::MemoryMonitor.format_memory(stats[:buffer_size])}"
    end
  end

  end_time = Time.now
  end_memory = Wp2txt::MemoryMonitor.current_memory_usage

  puts
  puts "Final Statistics:"
  final_stats = processor.stats
  puts "  Pages processed: #{final_stats[:pages_processed]}"
  puts "  Bytes read: #{Wp2txt::MemoryMonitor.format_memory(final_stats[:bytes_read])}"
  puts "  Final buffer size: #{Wp2txt::MemoryMonitor.format_memory(final_stats[:buffer_size])}"
  puts "  Processing time: #{(end_time - start_time).round(3)}s"
  puts "  Memory delta: #{Wp2txt::MemoryMonitor.format_memory(end_memory - start_memory)}"

  # Test without adaptive buffer
  puts
  puts "Testing with fixed buffer sizing (10 MB):"
  puts "-" * 40

  processor2 = Wp2txt::StreamProcessor.new(input_file, adaptive_buffer: false)
  puts "Fixed buffer size: #{Wp2txt::MemoryMonitor.format_memory(processor2.buffer_size)}"

  start_time = Time.now
  start_memory = Wp2txt::MemoryMonitor.current_memory_usage

  page_count = 0
  processor2.each_page do |_title, _text|
    page_count += 1
  end

  end_time = Time.now
  end_memory = Wp2txt::MemoryMonitor.current_memory_usage

  final_stats = processor2.stats
  puts "  Pages processed: #{final_stats[:pages_processed]}"
  puts "  Processing time: #{(end_time - start_time).round(3)}s"
  puts "  Memory delta: #{Wp2txt::MemoryMonitor.format_memory(end_memory - start_memory)}"
end

def main
  profile_memory_monitor

  input_file = ARGV[0] || "/tmp/wp2txt_test_sample.xml"
  profile_stream_processor(input_file)

  print_separator("Memory Profiling Complete")
  puts "Current memory: #{Wp2txt::MemoryMonitor.format_memory(Wp2txt::MemoryMonitor.current_memory_usage)}"
  puts "Memory low?: #{Wp2txt::MemoryMonitor.memory_low?}"
end

main
