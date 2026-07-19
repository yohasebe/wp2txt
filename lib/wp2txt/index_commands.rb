# frozen_string_literal: true

require "json"
require_relative "metadata_index"
require_relative "multistream"
require_relative "memory_monitor"

module Wp2txt
  # CLI command handlers for --build-index and --find-articles.
  # Mixed into WpApp (bin/wp2txt); relies on CliUI helpers for output.
  module IndexCommands
    # Build (or refresh) the local metadata index for a dump
    def run_build_index(opts)
      multistream_path, index_path = resolve_dump_paths(opts, download: true)
      return CliUI::EXIT_ERROR unless multistream_path

      db_path = MetadataIndex.path_for(multistream_path, cache_dir: opts[:cache_dir])
      meta = MetadataIndex.new(db_path)

      if meta.valid_for?(multistream_path) && !opts[:update_cache]
        print_success("Metadata index is up to date: #{db_path}")
        print_index_stats(meta.stats)
        meta.close
        return CliUI::EXIT_SUCCESS
      end
      meta.close

      print_mode_banner("Build Metadata Index", {
        "Dump" => File.basename(multistream_path),
        "Output" => db_path
      })

      time_start = Time.now
      puts pastel.cyan("Loading multistream index...") unless quiet?
      ms_index = MultistreamIndex.new(index_path, cache_dir: opts[:cache_dir], show_progress: !quiet?)
      if ms_index.stream_offsets.empty?
        print_error("Multistream index is empty or unreadable: #{index_path}")
        return CliUI::EXIT_ERROR
      end

      num_processes = opts[:num_procs] || MemoryMonitor.optimal_processes
      puts pastel.cyan("Scanning #{ms_index.size} pages in #{ms_index.stream_offsets.size} streams (#{num_processes} processes)...") unless quiet?

      builder = MetadataIndexBuilder.new(
        multistream_path, ms_index.stream_offsets,
        db_path: db_path, num_processes: num_processes
      )

      last_report = Time.now
      built = builder.build do |done, total|
        now = Time.now
        if !quiet? && (now - last_report >= DEFAULT_PROGRESS_INTERVAL || done == total)
          last_report = now
          percent = (done.to_f / total * 100).round(1)
          elapsed = now - time_start
          eta = done.positive? ? (total - done) * (elapsed / done) : 0
          puts pastel.dim(format("  [%d/%d] %.1f%% | ETA: %s", done, total, percent, format_duration(eta)))
        end
      end

      puts unless quiet?
      print_success("Metadata index built in #{format_duration(Time.now - time_start)}")
      print_index_stats(built.stats)
      built.close
      CliUI::EXIT_SUCCESS
    end

    # Query the metadata index and print matching article titles
    def run_find_articles(opts)
      multistream_path, = resolve_dump_paths(opts, download: false)
      return CliUI::EXIT_ERROR unless multistream_path

      db_path = MetadataIndex.path_for(multistream_path, cache_dir: opts[:cache_dir])
      meta = MetadataIndex.new(db_path)

      unless meta.built?
        print_error("Metadata index not found for this dump.")
        print_info_message("Build it first with: wp2txt --build-index #{opts[:lang] ? "-L #{opts[:lang]}" : "-i #{opts[:input]}"}")
        return CliUI::EXIT_ERROR
      end

      unless meta.valid_for?(multistream_path)
        print_warning("Metadata index was built from a different version of this dump. Consider re-running --build-index.")
      end

      filters = {
        category: opts[:in_category],
        depth: opts[:in_category] ? opts[:depth] : 0,
        has_section: opts[:has_section],
        use_aliases: !opts[:no_section_aliases],
        alias_file: opts[:alias_file],
        title_match: opts[:title_match]
      }

      total = meta.count_articles(**filters)
      titles = meta.find_articles(**filters, limit: opts[:limit])
      dump_name = meta.stats[:dump_name]
      meta.close

      if opts[:format].to_s.downcase == "json"
        puts JSON.generate({ dump: dump_name, total: total, returned: titles.size, titles: titles })
      else
        titles.each { |t| puts t }
        $stderr.puts pastel.dim("# #{titles.size} of #{total} matching articles (dump: #{dump_name})")
      end
      CliUI::EXIT_SUCCESS
    end

    private

    def print_index_stats(stats)
      return unless stats && !quiet?

      print_info("Dump", stats[:dump_name].to_s)
      print_info("Pages", stats[:page_count].to_s)
      print_info("Articles", stats[:article_count].to_s)
      print_info("Categories", stats[:category_count].to_s)
      print_info("Sections", stats[:section_count].to_s)
      print_info("Size", format_size(stats[:db_size]))
    end

    # Resolve [multistream_path, index_path] from --lang (cached dump) or --input.
    # Returns [nil, nil] after printing an error when files cannot be located.
    def resolve_dump_paths(opts, download: false)
      if opts[:lang]
        manager = DumpManager.new(
          opts[:lang],
          cache_dir: opts[:cache_dir],
          dump_expiry_days: CLI.config.dump_expiry_days
        )
        multistream = manager.cached_multistream_path
        index = manager.cached_index_path
        unless File.exist?(multistream) && File.exist?(index)
          unless download
            print_error("No cached dump found for '#{opts[:lang]}'.")
            print_info_message("Download and index it with: wp2txt --build-index -L #{opts[:lang]}")
            return [nil, nil]
          end
          print_header("Downloading dump files for '#{opts[:lang]}'")
          manager.download_index
          manager.download_multistream
        end
        [multistream, index]
      else
        multistream = opts[:input]
        index = locate_index_file(multistream)
        unless index
          print_error("Could not find the multistream index file for #{multistream}")
          print_info_message("Expected e.g. #{File.basename(multistream).sub(/multistream\.xml\.bz2\z/, 'multistream-index.txt.bz2')} next to the dump.")
          return [nil, nil]
        end
        [multistream, index]
      end
    end

    def locate_index_file(multistream_path)
      candidates = [
        multistream_path.sub(/multistream\.xml\.bz2\z/, "multistream-index.txt.bz2"),
        multistream_path.sub(/\.xml\.bz2\z/, "-index.txt.bz2"),
        multistream_path.sub(/\.xml\.bz2\z/, "-index.txt")
      ].uniq
      candidates.find { |c| c != multistream_path && File.exist?(c) }
    end
  end
end
