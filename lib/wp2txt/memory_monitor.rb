# frozen_string_literal: true

require "etc"

module Wp2txt
  # Memory monitoring and adaptive buffer sizing for streaming operations
  # Provides utilities to track memory usage and dynamically adjust buffer sizes
  module MemoryMonitor
    # Default memory thresholds
    LOW_MEMORY_THRESHOLD_MB = 256
    HIGH_MEMORY_THRESHOLD_MB = 1024
    TARGET_MEMORY_USAGE_PERCENT = 70

    # Buffer size bounds
    MIN_BUFFER_SIZE = 1_048_576     # 1 MB minimum
    MAX_BUFFER_SIZE = 104_857_600   # 100 MB maximum
    DEFAULT_BUFFER_SIZE = 10_485_760 # 10 MB default

    module_function

    # Get current process memory usage in bytes
    # @return [Integer] Memory usage in bytes, or 0 if unavailable
    def current_memory_usage
      if Gem.win_platform?
        # Windows: use tasklist (less reliable)
        begin
          output = `tasklist /FI "PID eq #{Process.pid}" /FO CSV /NH 2>NUL`
          # Parse CSV format: "process.exe","PID","Session","Session#","Mem Usage"
          if output =~ /(\d[\d,]*)\s*K/
            return $1.delete(",").to_i * 1024
          end
        rescue StandardError
          return 0
        end
      else
        # Unix: use /proc or ps
        if File.exist?("/proc/#{Process.pid}/status")
          # Linux: read from /proc
          File.read("/proc/#{Process.pid}/status").each_line do |line|
            if line =~ /^VmRSS:\s*(\d+)\s*kB/
              return $1.to_i * 1024
            end
          end
        else
          # macOS/BSD: use ps
          begin
            output = `ps -o rss= -p #{Process.pid} 2>/dev/null`
            return output.strip.to_i * 1024 unless output.strip.empty?
          rescue StandardError
            return 0
          end
        end
      end
      0
    end

    # Get total system memory in bytes
    # @return [Integer] Total memory in bytes, or default if unavailable
    def total_system_memory
      if Gem.win_platform?
        # Windows: use wmic
        begin
          output = `wmic computersystem get TotalPhysicalMemory 2>NUL`
          if output =~ /(\d+)/
            return $1.to_i
          end
        rescue StandardError
          return 4 * 1024 * 1024 * 1024 # Default 4 GB
        end
      elsif File.exist?("/proc/meminfo")
        # Linux
        File.read("/proc/meminfo").each_line do |line|
          if line =~ /^MemTotal:\s*(\d+)\s*kB/
            return $1.to_i * 1024
          end
        end
      else
        # macOS: use sysctl
        begin
          output = `sysctl -n hw.memsize 2>/dev/null`
          return output.strip.to_i unless output.strip.empty?
        rescue StandardError
          return 4 * 1024 * 1024 * 1024 # Default 4 GB
        end
      end
      4 * 1024 * 1024 * 1024 # Default 4 GB
    end

    # Get available (free) memory in bytes
    # @return [Integer] Available memory in bytes
    def available_memory
      if File.exist?("/proc/meminfo")
        # Linux: read MemAvailable or estimate from MemFree + Buffers + Cached
        meminfo = File.read("/proc/meminfo")
        if meminfo =~ /^MemAvailable:\s*(\d+)\s*kB/
          return $1.to_i * 1024
        end

        free = buffers = cached = 0
        meminfo.each_line do |line|
          case line
          when /^MemFree:\s*(\d+)\s*kB/
            free = $1.to_i * 1024
          when /^Buffers:\s*(\d+)\s*kB/
            buffers = $1.to_i * 1024
          when /^Cached:\s*(\d+)\s*kB/
            cached = $1.to_i * 1024
          end
        end
        return free + buffers + cached
      else
        # macOS/other: estimate as total - current usage
        total_system_memory - current_memory_usage
      end
    end

    # Calculate memory usage percentage
    # @return [Float] Percentage of memory used (0-100)
    def memory_usage_percent
      total = total_system_memory
      return 0.0 if total.zero?

      (current_memory_usage.to_f / total * 100).round(2)
    end

    # Determine if memory is running low
    # @return [Boolean] true if memory usage is high
    def memory_low?
      available = available_memory / (1024 * 1024) # Convert to MB
      available < LOW_MEMORY_THRESHOLD_MB
    end

    # Calculate optimal buffer size based on available memory
    # @param target_percent [Integer] Target memory usage percentage (default: 70%)
    # @return [Integer] Recommended buffer size in bytes
    def optimal_buffer_size(target_percent: TARGET_MEMORY_USAGE_PERCENT)
      available = available_memory

      # Use a fraction of available memory for buffering
      # Conservative: use only 10% of available memory for buffer
      target_buffer = (available * 0.10).to_i

      # Clamp to reasonable bounds
      target_buffer = MIN_BUFFER_SIZE if target_buffer < MIN_BUFFER_SIZE
      target_buffer = MAX_BUFFER_SIZE if target_buffer > MAX_BUFFER_SIZE

      # Round to nearest MB for cleaner allocation
      ((target_buffer / 1_048_576.0).round * 1_048_576).to_i
    end

    # Get a summary of current memory status
    # @return [Hash] Memory statistics
    def memory_stats
      {
        current_usage_mb: (current_memory_usage / 1_048_576.0).round(2),
        total_system_mb: (total_system_memory / 1_048_576.0).round(2),
        available_mb: (available_memory / 1_048_576.0).round(2),
        usage_percent: memory_usage_percent,
        recommended_buffer_mb: (optimal_buffer_size / 1_048_576.0).round(2),
        low_memory: memory_low?
      }
    end

    # Format memory size for display
    # @param bytes [Integer] Size in bytes
    # @return [String] Human-readable size
    def format_memory(bytes)
      if bytes < 1024
        "#{bytes} B"
      elsif bytes < 1_048_576
        "#{(bytes / 1024.0).round(1)} KB"
      elsif bytes < 1_073_741_824
        "#{(bytes / 1_048_576.0).round(1)} MB"
      else
        "#{(bytes / 1_073_741_824.0).round(2)} GB"
      end
    end

    # Run garbage collection if memory is low
    # @return [Boolean] true if GC was triggered
    def gc_if_needed
      if memory_low?
        GC.start
        true
      else
        false
      end
    end

    # Memory required per parallel process (estimated)
    MEMORY_PER_PROCESS_MB = 300

    # Calculate optimal number of parallel processes based on CPU and memory
    # @param memory_per_process_mb [Integer] Estimated memory per process in MB
    # @return [Integer] Recommended number of parallel processes
    def optimal_processes(memory_per_process_mb: MEMORY_PER_PROCESS_MB)
      cores = Etc.nprocessors

      # CPU-based calculation (scale based on core count)
      cpu_based = case cores
                  when 1..4
                    [cores - 1, 1].max
                  when 5..8
                    cores - 2
                  else
                    # Large systems: use 75% of cores
                    (cores * 0.75).to_i
                  end

      # Memory-based limit
      available_mb = available_memory / (1024 * 1024)
      memory_based = (available_mb / memory_per_process_mb).to_i

      # Use the smaller of CPU and memory limits, minimum 1
      result = [cpu_based, memory_based].min
      [result, 1].max
    end

    # Get system info for parallel processing decisions
    # @return [Hash] System information
    def parallel_processing_info
      cores = Etc.nprocessors
      available_mb = (available_memory / 1_048_576.0).round(0)
      optimal = optimal_processes

      {
        cpu_cores: cores,
        available_memory_mb: available_mb,
        memory_per_process_mb: MEMORY_PER_PROCESS_MB,
        optimal_processes: optimal,
        max_by_cpu: cores,
        max_by_memory: (available_mb / MEMORY_PER_PROCESS_MB).to_i
      }
    end
  end
end
