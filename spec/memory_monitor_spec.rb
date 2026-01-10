# frozen_string_literal: true

require "spec_helper"
require "wp2txt/memory_monitor"

RSpec.describe Wp2txt::MemoryMonitor do
  describe ".current_memory_usage" do
    it "returns a non-negative integer" do
      usage = described_class.current_memory_usage
      expect(usage).to be_a(Integer)
      expect(usage).to be >= 0
    end
  end

  describe ".total_system_memory" do
    it "returns a positive integer" do
      total = described_class.total_system_memory
      expect(total).to be_a(Integer)
      expect(total).to be > 0
    end

    it "returns at least 1 GB (reasonable minimum for running tests)" do
      total = described_class.total_system_memory
      one_gb = 1024 * 1024 * 1024
      expect(total).to be >= one_gb
    end
  end

  describe ".available_memory" do
    it "returns a positive integer" do
      available = described_class.available_memory
      expect(available).to be_a(Integer)
      expect(available).to be > 0
    end

    it "is less than or equal to total system memory" do
      available = described_class.available_memory
      total = described_class.total_system_memory
      expect(available).to be <= total
    end
  end

  describe ".memory_usage_percent" do
    it "returns a float between 0 and 100" do
      percent = described_class.memory_usage_percent
      expect(percent).to be_a(Float)
      expect(percent).to be >= 0
      expect(percent).to be <= 100
    end
  end

  describe ".memory_low?" do
    it "returns a boolean" do
      result = described_class.memory_low?
      expect([true, false]).to include(result)
    end
  end

  describe ".optimal_buffer_size" do
    it "returns an integer within bounds" do
      size = described_class.optimal_buffer_size
      expect(size).to be_a(Integer)
      expect(size).to be >= described_class::MIN_BUFFER_SIZE
      expect(size).to be <= described_class::MAX_BUFFER_SIZE
    end

    it "returns a multiple of 1 MB" do
      size = described_class.optimal_buffer_size
      one_mb = 1_048_576
      expect(size % one_mb).to eq(0)
    end
  end

  describe ".memory_stats" do
    it "returns a hash with expected keys" do
      stats = described_class.memory_stats
      expect(stats).to be_a(Hash)
      expect(stats).to have_key(:current_usage_mb)
      expect(stats).to have_key(:total_system_mb)
      expect(stats).to have_key(:available_mb)
      expect(stats).to have_key(:usage_percent)
      expect(stats).to have_key(:recommended_buffer_mb)
      expect(stats).to have_key(:low_memory)
    end

    it "returns numeric values for memory metrics" do
      stats = described_class.memory_stats
      expect(stats[:current_usage_mb]).to be_a(Numeric)
      expect(stats[:total_system_mb]).to be_a(Numeric)
      expect(stats[:available_mb]).to be_a(Numeric)
      expect(stats[:usage_percent]).to be_a(Numeric)
      expect(stats[:recommended_buffer_mb]).to be_a(Numeric)
    end
  end

  describe ".format_memory" do
    it "formats bytes" do
      expect(described_class.format_memory(500)).to eq("500 B")
    end

    it "formats kilobytes" do
      expect(described_class.format_memory(2048)).to eq("2.0 KB")
    end

    it "formats megabytes" do
      expect(described_class.format_memory(5_242_880)).to eq("5.0 MB")
    end

    it "formats gigabytes" do
      expect(described_class.format_memory(2_147_483_648)).to eq("2.0 GB")
    end
  end

  describe ".gc_if_needed" do
    it "returns a boolean" do
      result = described_class.gc_if_needed
      expect([true, false]).to include(result)
    end
  end

  describe "constants" do
    it "has reasonable threshold values" do
      expect(described_class::LOW_MEMORY_THRESHOLD_MB).to be > 0
      expect(described_class::HIGH_MEMORY_THRESHOLD_MB).to be > described_class::LOW_MEMORY_THRESHOLD_MB
      expect(described_class::TARGET_MEMORY_USAGE_PERCENT).to be_between(50, 90)
    end

    it "has reasonable buffer size bounds" do
      expect(described_class::MIN_BUFFER_SIZE).to be > 0
      expect(described_class::MAX_BUFFER_SIZE).to be > described_class::MIN_BUFFER_SIZE
      expect(described_class::DEFAULT_BUFFER_SIZE).to be >= described_class::MIN_BUFFER_SIZE
      expect(described_class::DEFAULT_BUFFER_SIZE).to be <= described_class::MAX_BUFFER_SIZE
    end

    it "has reasonable memory per process value" do
      expect(described_class::MEMORY_PER_PROCESS_MB).to be_between(100, 1000)
    end
  end

  describe ".optimal_processes" do
    it "returns a positive integer" do
      result = described_class.optimal_processes
      expect(result).to be_a(Integer)
      expect(result).to be >= 1
    end

    it "returns a value less than or equal to CPU cores" do
      result = described_class.optimal_processes
      cores = Etc.nprocessors
      expect(result).to be <= cores
    end

    it "accepts custom memory_per_process_mb parameter" do
      # With very high memory requirement, should return fewer processes
      high_mem = described_class.optimal_processes(memory_per_process_mb: 10_000)
      low_mem = described_class.optimal_processes(memory_per_process_mb: 100)
      expect(high_mem).to be <= low_mem
    end

    it "returns at least 1 even with extreme memory constraints" do
      result = described_class.optimal_processes(memory_per_process_mb: 1_000_000)
      expect(result).to be >= 1
    end
  end

  describe ".parallel_processing_info" do
    it "returns a hash with expected keys" do
      info = described_class.parallel_processing_info
      expect(info).to be_a(Hash)
      expect(info).to have_key(:cpu_cores)
      expect(info).to have_key(:available_memory_mb)
      expect(info).to have_key(:memory_per_process_mb)
      expect(info).to have_key(:optimal_processes)
      expect(info).to have_key(:max_by_cpu)
      expect(info).to have_key(:max_by_memory)
    end

    it "returns consistent values" do
      info = described_class.parallel_processing_info
      expect(info[:cpu_cores]).to eq(Etc.nprocessors)
      expect(info[:memory_per_process_mb]).to eq(described_class::MEMORY_PER_PROCESS_MB)
      expect(info[:optimal_processes]).to eq(described_class.optimal_processes)
    end

    it "returns positive values for all numeric fields" do
      info = described_class.parallel_processing_info
      expect(info[:cpu_cores]).to be > 0
      expect(info[:available_memory_mb]).to be > 0
      expect(info[:optimal_processes]).to be > 0
    end
  end
end
