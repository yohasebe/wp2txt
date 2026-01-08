# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core"
require "rspec/core/rake_task"
require_relative "./lib/wp2txt/version"

class String
  def strip_heredoc
    gsub(/^#{scan(/^[ \t]*(?=\S)/).min}/, "")
  end
end

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList["spec/**/*_spec.rb"]
end

task default: :spec

# =============================================================================
# Test Data Management
# =============================================================================

namespace :testdata do
  desc "Show test data cache status"
  task :status do
    require_relative "./lib/wp2txt/test_data_manager"

    status = Wp2txt::TestDataManager.status
    puts "\n=== Test Data Cache Status ==="
    status.each do |lang, levels|
      puts "\n#{lang}:"
      levels.each do |level, info|
        status_str = info[:cached] ? (info[:fresh] ? "✅ fresh" : "⚠️  stale") : "❌ missing"
        puts "  #{level}: #{status_str}"
      end
    end
    puts
  end

  desc "Download and cache test data for a language (partial download, ~500-1000 articles)"
  task :prepare, [:lang, :streams] do |t, args|
    require_relative "./lib/wp2txt/multistream"

    lang = (args[:lang] || "en").to_sym
    max_streams = (args[:streams] || "10").to_i

    puts "Preparing test data: #{lang} (first #{max_streams} streams)"

    dump_manager = Wp2txt::DumpManager.new(lang, cache_dir: "tmp/test_cache/dumps")

    # Download index first
    puts "\n=== Downloading index ==="
    index_path = dump_manager.download_index

    # Partial download of multistream
    puts "\n=== Downloading partial multistream ==="
    multistream_path = dump_manager.download_multistream(max_streams: max_streams)

    # Extract articles
    puts "\n=== Extracting articles ==="
    reader = Wp2txt::MultistreamReader.new(multistream_path, index_path)

    articles = []
    stream_count = 0
    reader.each_article_in_first_streams(max_streams) do |page|
      articles << {
        title: page[:title],
        id: page[:id],
        text: page[:text]
      }
      if articles.size % 50 == 0
        print "\r  Extracted: #{articles.size} articles"
        $stdout.flush
      end
    end
    puts "\r  Extracted: #{articles.size} articles (done)"

    # Save to cache
    require "json"
    require "fileutils"
    cache_path = "tmp/test_cache/#{lang}/test_#{max_streams}streams.json"
    FileUtils.mkdir_p(File.dirname(cache_path))
    File.write(cache_path, JSON.pretty_generate(articles))

    puts "Ready: #{articles.size} articles cached to #{cache_path}"
  end

  desc "Prepare test data for all supported languages"
  task :prepare_all, [:streams] do |t, args|
    require_relative "./lib/wp2txt/multistream"

    max_streams = (args[:streams] || "10").to_i
    languages = [:en, :zh, :ja, :ru, :ar, :ko]

    languages.each do |lang|
      puts "\n" + "=" * 60
      puts "=== Preparing #{lang} ==="
      puts "=" * 60
      Rake::Task["testdata:prepare"].reenable
      Rake::Task["testdata:prepare"].invoke(lang, max_streams)
    end
  end

  # =========================================================================
  # Tier-based Test Data Management
  # =========================================================================

  desc "Show tier-based test data status"
  task :tier_status do
    require_relative "./lib/wp2txt/test_data_manager"
    Wp2txt::TestDataManager.print_tier_status
  end

  desc "Prepare test data for a specific tier (tier1, tier2, tier3, tier4)"
  task :prepare_tier, [:tier] do |t, args|
    require_relative "./lib/wp2txt/test_data_manager"
    require_relative "./lib/wp2txt/multistream"
    require "json"
    require "fileutils"

    tier_name = args[:tier] || "tier1"
    languages = Wp2txt::TestDataManager.languages_in_tier(tier_name)

    if languages.empty?
      puts "No languages in #{tier_name}"
      exit 1
    end

    puts "=== Preparing #{tier_name.upcase} ==="
    puts "Languages: #{languages.size}"
    puts

    languages.each_with_index do |lang, idx|
      sample_size = Wp2txt::TestDataManager.sample_size_for(lang)
      puts "\n[#{idx + 1}/#{languages.size}] #{lang} (#{sample_size} articles)"
      $stdout.flush

      begin
        # Estimate streams needed (roughly 100 articles per stream)
        streams_needed = [(sample_size / 100.0).ceil + 1, 1].max

        dump_manager = Wp2txt::DumpManager.new(lang, cache_dir: "tmp/test_cache/dumps")

        # Download index
        index_path = dump_manager.download_index
        multistream_path = dump_manager.download_multistream(max_streams: streams_needed)

        # Extract articles
        print "  Loading index..."
        $stdout.flush
        reader = Wp2txt::MultistreamReader.new(multistream_path, index_path)
        puts " done (#{reader.index.size} articles in index)"

        print "  Extracting articles: "
        $stdout.flush
        articles = []

        reader.each_article_in_first_streams(streams_needed) do |page|
          articles << {
            title: page[:title],
            id: page[:id],
            text: page[:text]
          }
          if articles.size % 100 == 0
            print "\r  Extracting articles: #{articles.size}/#{sample_size}"
            $stdout.flush
          end
          break if articles.size >= sample_size
        end
        puts "\r  Extracting articles: #{articles.size}/#{sample_size} done"

        # Save to cache
        cache_path = "tmp/test_cache/#{lang}/tier_#{sample_size}.json"
        FileUtils.mkdir_p(File.dirname(cache_path))
        File.write(cache_path, JSON.pretty_generate(articles))

        puts "  ✓ Cached #{articles.size} articles"
      rescue StandardError => e
        puts "  ✗ Error: #{e.message}"
      end
    end

    puts "\n=== #{tier_name.upcase} Complete ==="
  end

  desc "Prepare test data for all tiers"
  task :prepare_all_tiers do
    %w[tier1 tier2 tier3 tier4].each do |tier|
      Rake::Task["testdata:prepare_tier"].reenable
      Rake::Task["testdata:prepare_tier"].invoke(tier)
    end
  end
end

# =============================================================================
# Validation
# =============================================================================

namespace :validate do
  desc "Run validation on cached test data"
  task :run, [:lang, :streams] do |t, args|
    require_relative "./lib/wp2txt"
    require_relative "./lib/wp2txt/article"
    require_relative "./lib/wp2txt/utils"
    require_relative "./lib/wp2txt/test_data_manager"
    require "json"

    include Wp2txt

    lang = (args[:lang] || "en").to_sym
    streams = (args[:streams] || "10").to_i
    cache_path = "tmp/test_cache/#{lang}/test_#{streams}streams.json"

    unless File.exist?(cache_path)
      puts "Cache not found. Run: rake testdata:prepare[#{lang},#{streams}]"
      exit 1
    end

    puts "=== Validation: #{lang} (#{streams} streams) ==="

    articles = JSON.parse(File.read(cache_path), symbolize_names: true)
    puts "Loaded #{articles.size} articles"

    detector = Wp2txt::IssueDetector.new
    processed = 0

    articles.each do |article_data|
      start_time = Time.now

      begin
        article = Wp2txt::Article.new(article_data[:text], article_data[:title], true)

        output = +""
        article.elements.each do |type, content|
          next unless content

          case type
          when :mw_heading, :mw_paragraph, :mw_link, :mw_ml_link
            output << format_wiki(content, {}) << "\n"
          when :mw_unordered, :mw_ordered, :mw_definition
            output << format_wiki(content, {}) << "\n"
          when :mw_isolated_tag
            output << format_wiki(content, {}) << "\n"
          end
        end
        output = cleanup(output)

        processing_time = Time.now - start_time

        detector.analyze(
          title: article_data[:title],
          input: article_data[:text],
          output: output,
          processing_time: processing_time
        )
      rescue StandardError => e
        detector.analyze(
          title: article_data[:title],
          input: article_data[:text],
          output: "",
          processing_time: nil
        )
        puts "  Error: #{article_data[:title]}: #{e.message}"
      end

      processed += 1
      if processed % 10 == 0
        print "\r  Processed: #{processed}/#{articles.size}"
        $stdout.flush
      end
    end

    puts "\n\n=== Summary ==="
    summary = detector.summary
    puts "Analyzed: #{summary[:total_analyzed]} articles (#{summary[:skipped_non_articles]} non-article pages skipped)"
    puts "Articles with issues: #{summary[:total_articles_with_issues]} (#{summary[:issue_rate]}%)"
    if summary[:issues_by_type].any?
      puts "\nIssues by type:"
      summary[:issues_by_type].each do |type, count|
        puts "  #{type}: #{count}"
      end
    end

    # Save log
    log_path = "tmp/validation/#{lang}_#{streams}streams_#{Time.now.strftime('%Y%m%d_%H%M%S')}.jsonl"
    detector.save(log_path)
  end

  desc "Run validation on all supported languages"
  task :run_all, [:streams] do |t, args|
    streams = (args[:streams] || "10").to_i
    languages = [:en, :zh, :ja, :ru, :ar, :ko]

    languages.each do |lang|
      puts "\n" + "=" * 60
      Rake::Task["validate:run"].reenable
      Rake::Task["validate:run"].invoke(lang, streams)
    end
  end

  desc "Run full validation on complete dump"
  task :full, [:lang] do |t, args|
    require_relative "./lib/wp2txt"
    require_relative "./lib/wp2txt/article"
    require_relative "./lib/wp2txt/utils"
    require_relative "./lib/wp2txt/multistream"
    require_relative "./lib/wp2txt/test_data_manager"

    include Wp2txt

    lang = (args[:lang] || "ja").to_sym

    puts "=== Full Validation: #{lang} ==="
    puts "This may take several hours..."

    dump_manager = Wp2txt::DumpManager.new(lang)
    dump_manager.download_index
    dump_manager.download_multistream

    reader = Wp2txt::MultistreamReader.new(
      dump_manager.cached_multistream_path,
      dump_manager.cached_index_path
    )

    detector = Wp2txt::IssueDetector.new
    processed = 0
    start_time = Time.now

    reader.index.stream_offsets.each_with_index do |offset, stream_idx|
      reader.each_article_in_stream(offset) do |page|
        begin
          article = Wp2txt::Article.new(page[:text], page[:title], true)

          output = +""
          article.elements.each do |type, content|
            next unless content

            case type
            when :mw_heading, :mw_paragraph, :mw_link, :mw_ml_link
              output << format_wiki(content, {}) << "\n"
            when :mw_unordered, :mw_ordered, :mw_definition
              output << format_wiki(content, {}) << "\n"
            when :mw_isolated_tag
              # Process HTML content (e.g., <ul><li> lists)
              output << format_wiki(content, {}) << "\n"
            end
          end
          output = cleanup(output)

          detector.analyze(
            title: page[:title],
            input: page[:text],
            output: output
          )
        rescue StandardError => e
          detector.analyze(
            title: page[:title],
            input: page[:text],
            output: ""
          )
        end

        processed += 1

        if processed % 1000 == 0
          elapsed = Time.now - start_time
          rate = processed / elapsed
          print "\r  Processed: #{processed} (#{rate.round(1)} articles/sec)"
          $stdout.flush
        end
      end

      # Periodic save
      if stream_idx % 100 == 0 && stream_idx > 0
        log_path = "tmp/validation/#{lang}_full_partial_#{stream_idx}.jsonl"
        detector.save(log_path)
      end
    end

    elapsed = Time.now - start_time
    summary = detector.summary
    puts "\n\nCompleted in #{(elapsed / 60).round(1)} minutes"
    puts "Analyzed: #{summary[:total_analyzed]} articles (#{summary[:skipped_non_articles]} non-article pages skipped)"
    puts "Issues: #{summary[:total_articles_with_issues]} (#{summary[:issue_rate]}%)"

    # Save final log
    log_path = "tmp/validation/#{lang}_full_#{Time.now.strftime('%Y%m%d_%H%M%S')}.jsonl"
    detector.save(log_path)
  end

  desc "Generate report from validation logs"
  task :report, [:log_path] do |t, args|
    require "json"

    log_path = args[:log_path]
    raise "Please specify log path" unless log_path

    issues = []
    File.foreach(log_path) do |line|
      issues << JSON.parse(line, symbolize_names: true)
    end

    puts "=== Validation Report ==="
    puts "Total articles with issues: #{issues.size}"

    # Aggregate by type
    type_counts = Hash.new(0)
    type_samples = Hash.new { |h, k| h[k] = [] }

    issues.each do |article|
      article[:issues].each do |issue|
        type = issue[:type].to_sym
        type_counts[type] += 1
        type_samples[type] << { title: article[:title], context: issue[:context] } if type_samples[type].size < 5
      end
    end

    puts "\nIssues by type:"
    type_counts.sort_by { |_, v| -v }.each do |type, count|
      puts "\n#{type}: #{count}"
      type_samples[type].each do |sample|
        puts "  - #{sample[:title]}: #{sample[:context][0..80]}"
      end
    end
  end

  # =========================================================================
  # Tier-based Validation
  # =========================================================================

  desc "Validate a specific tier"
  task :tier, [:tier] do |t, args|
    require_relative "./lib/wp2txt"
    require_relative "./lib/wp2txt/article"
    require_relative "./lib/wp2txt/utils"
    require_relative "./lib/wp2txt/test_data_manager"
    require "json"

    include Wp2txt

    tier_name = args[:tier] || "tier1"
    languages = Wp2txt::TestDataManager.languages_in_tier(tier_name)

    if languages.empty?
      puts "No languages in #{tier_name}"
      exit 1
    end

    puts "=== Validating #{tier_name.upcase} ==="
    puts "Languages: #{languages.size}"

    tier_summary = {}

    languages.each_with_index do |lang, idx|
      sample_size = Wp2txt::TestDataManager.sample_size_for(lang)
      cache_path = "tmp/test_cache/#{lang}/tier_#{sample_size}.json"

      unless File.exist?(cache_path)
        puts "\n[#{idx + 1}/#{languages.size}] #{lang}: ❌ Cache missing"
        tier_summary[lang] = { status: :missing }
        next
      end

      puts "\n[#{idx + 1}/#{languages.size}] #{lang} (#{sample_size} articles)"

      begin
        articles = JSON.parse(File.read(cache_path), symbolize_names: true)
        detector = Wp2txt::IssueDetector.new

        articles.each do |article_data|
          begin
            article = Wp2txt::Article.new(article_data[:text], article_data[:title], true)

            output = +""
            article.elements.each do |type, content|
              next unless content

              case type
              when :mw_heading, :mw_paragraph, :mw_link, :mw_ml_link
                output << format_wiki(content, {}) << "\n"
              when :mw_unordered, :mw_ordered, :mw_definition
                output << format_wiki(content, {}) << "\n"
              when :mw_isolated_tag
                output << format_wiki(content, {}) << "\n"
              end
            end
            output = cleanup(output)

            detector.analyze(
              title: article_data[:title],
              input: article_data[:text],
              output: output
            )
          rescue StandardError => e
            detector.analyze(
              title: article_data[:title],
              input: article_data[:text],
              output: ""
            )
          end
        end

        summary = detector.summary
        issue_count = summary[:total_articles_with_issues]
        analyzed = summary[:total_analyzed]
        skipped = summary[:skipped_non_articles]
        rate = summary[:issue_rate]

        puts "  ✓ #{analyzed} articles analyzed (#{skipped} non-article pages skipped)"
        puts "    Issues: #{issue_count} (#{rate}%)"

        tier_summary[lang] = {
          status: :ok,
          articles: analyzed,
          skipped: skipped,
          issues: issue_count,
          rate: rate
        }

        # Save log
        log_path = "tmp/validation/#{tier_name}_#{lang}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.jsonl"
        detector.save(log_path)
      rescue StandardError => e
        puts "  ✗ Error: #{e.message}"
        tier_summary[lang] = { status: :error, message: e.message }
      end
    end

    # Print tier summary
    puts "\n" + "=" * 60
    puts "=== #{tier_name.upcase} Summary ==="
    ok_count = tier_summary.count { |_, v| v[:status] == :ok }
    total_articles = tier_summary.values.sum { |v| v[:articles] || 0 }
    total_skipped = tier_summary.values.sum { |v| v[:skipped] || 0 }
    total_issues = tier_summary.values.sum { |v| v[:issues] || 0 }
    overall_rate = total_articles > 0 ? (total_issues.to_f / total_articles * 100).round(2) : 0

    puts "Languages: #{ok_count}/#{languages.size} validated"
    puts "Articles analyzed: #{total_articles} (#{total_skipped} non-article pages skipped)"
    puts "Issues: #{total_issues} (#{overall_rate}%)"
  end

  desc "Validate all tiers"
  task :all_tiers do
    %w[tier1 tier2 tier3 tier4].each do |tier|
      Rake::Task["validate:tier"].reenable
      Rake::Task["validate:tier"].invoke(tier)
    end
  end
end

# =============================================================================
# Docker
# =============================================================================

desc "Push Docker images"
task :push do
  sh <<-SCRIPT.strip_heredoc, { verbose: false }
    /bin/bash -xeu <<'BASH'
      # docker buildx create --name mybuilder
      # docker buildx use mybuilder
      # docker buildx inspect --bootstrap
      docker buildx build --platform linux/amd64,linux/arm64 -t yohasebe/wp2txt:#{Wp2txt::VERSION} -t yohasebe/wp2txt:latest . --push
    BASH
  SCRIPT
end
