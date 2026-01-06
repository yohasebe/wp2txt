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

  desc "Download and cache test data for a language"
  task :prepare, [:lang, :level] do |t, args|
    require_relative "./lib/wp2txt/test_data_manager"

    lang = (args[:lang] || "en").to_sym
    level = (args[:level] || "unit").to_sym

    puts "Preparing test data: #{lang}/#{level}"
    manager = Wp2txt::TestDataManager.new(lang, level: level)
    articles = manager.articles
    puts "Ready: #{articles.size} articles cached"
  end

  desc "Refresh test data cache for a language"
  task :refresh, [:lang, :level] do |t, args|
    require_relative "./lib/wp2txt/test_data_manager"

    lang = (args[:lang] || "en").to_sym
    level = (args[:level] || "unit").to_sym

    puts "Refreshing test data: #{lang}/#{level}"
    manager = Wp2txt::TestDataManager.new(lang, level: level)
    manager.refresh!
  end

  desc "Prepare all test data for all languages"
  task :prepare_all do
    require_relative "./lib/wp2txt/test_data_manager"

    Wp2txt::TestDataManager::TEST_LANGUAGES.each do |lang|
      [:unit].each do |level|  # Only unit level for prepare_all
        puts "\n=== Preparing #{lang}/#{level} ==="
        manager = Wp2txt::TestDataManager.new(lang, level: level)
        articles = manager.articles
        puts "Ready: #{articles.size} articles"
      end
    end
  end
end

# =============================================================================
# Validation
# =============================================================================

namespace :validate do
  desc "Download dump files for a language"
  task :download, [:lang] do |t, args|
    require_relative "./lib/wp2txt/multistream"

    lang = (args[:lang] || "ja").to_sym
    manager = Wp2txt::DumpManager.new(lang)

    puts "Downloading dumps for #{lang}wiki (#{manager.latest_dump_date})..."
    manager.download_index
    manager.download_multistream
    puts "Done!"
  end

  desc "Run validation on cached test data"
  task :run, [:lang, :level] do |t, args|
    require_relative "./lib/wp2txt"
    require_relative "./lib/wp2txt/article"
    require_relative "./lib/wp2txt/utils"
    require_relative "./lib/wp2txt/test_data_manager"

    include Wp2txt

    lang = (args[:lang] || "ja").to_sym
    level = (args[:level] || "unit").to_sym

    puts "=== Validation: #{lang}/#{level} ==="

    manager = Wp2txt::TestDataManager.new(lang, level: level)
    articles = manager.articles
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
        puts "  Error processing #{article_data[:title]}: #{e.message}"
      end

      processed += 1
      print "\r  Processed: #{processed}/#{articles.size}" if processed % 10 == 0
    end

    puts "\n\n=== Summary ==="
    summary = detector.summary
    if summary.is_a?(String)
      puts summary
    else
      puts "Articles with issues: #{summary[:total_articles_with_issues]}"
      puts "\nIssues by type:"
      summary[:issues_by_type].each do |type, count|
        puts "  #{type}: #{count}"
      end
    end

    # Save detailed log
    log_path = "tmp/validation/#{lang}_#{level}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.jsonl"
    detector.save(log_path)
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
          puts "\r  Processed: #{processed} (#{rate.round(1)} articles/sec)"
        end
      end

      # Periodic save
      if stream_idx % 100 == 0 && stream_idx > 0
        log_path = "tmp/validation/#{lang}_full_partial_#{stream_idx}.jsonl"
        detector.save(log_path)
      end
    end

    elapsed = Time.now - start_time
    puts "\n\nCompleted: #{processed} articles in #{(elapsed / 60).round(1)} minutes"

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
