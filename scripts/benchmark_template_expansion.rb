#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark script to compare template expansion accuracy
# between wp2txt and MediaWiki (gold standard)
#
# Usage:
#   ruby scripts/benchmark_template_expansion.rb [options]
#
# Options:
#   --lang LANG      Wikipedia language code (default: en)
#   --count N        Number of articles to sample (default: 100)
#   --output DIR     Output directory (default: benchmark_results)
#   --use-cache      Use cached samples if available
#   --verbose        Show detailed output

require "bundler/setup"
require "optparse"
require "json"
require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "wp2txt"
require "wp2txt/article_sampler"
require "wp2txt/utils"

class TemplateBenchmark
  include Wp2txt

  def initialize(options = {})
    @lang = options[:lang] || "en"
    @count = options[:count] || 100
    @output_dir = options[:output_dir] || "benchmark_results"
    @use_cache = options[:use_cache] || false
    @verbose = options[:verbose] || false

    @samples_dir = File.join(@output_dir, "samples", @lang)
    @results_dir = File.join(@output_dir, "results")
  end

  def run
    puts "=" * 60
    puts "Template Expansion Benchmark"
    puts "=" * 60
    puts "Language: #{@lang}"
    puts "Sample size: #{@count}"
    puts

    # Step 1: Get samples
    articles = load_or_fetch_samples

    # Step 2: Process with wp2txt
    puts "\nProcessing with wp2txt..."
    wp2txt_results = process_with_wp2txt(articles)

    # Step 3: Compare results
    puts "\nComparing results..."
    comparison = compare_results(articles, wp2txt_results)

    # Step 4: Generate report
    generate_report(comparison)

    puts "\nBenchmark complete!"
    puts "Results saved to: #{@results_dir}"
  end

  private

  def load_or_fetch_samples
    metadata_path = File.join(@samples_dir, "articles.json")

    if @use_cache && File.exist?(metadata_path)
      puts "Loading cached samples from #{@samples_dir}..."
      metadata = JSON.parse(File.read(metadata_path))

      articles = metadata["articles"].map do |article|
        wikitext_path = File.join(@samples_dir, article["wikitext_file"])
        rendered_path = File.join(@samples_dir, article["rendered_file"])

        {
          title: article["title"],
          wikitext: File.read(wikitext_path),
          rendered: File.read(rendered_path)
        }
      end

      puts "Loaded #{articles.size} cached articles"
      articles
    else
      puts "Fetching #{@count} random articles from #{@lang}.wikipedia.org..."
      sampler = Wp2txt::ArticleSampler.new(lang: @lang, output_dir: @samples_dir)
      sampler.sample(@count)

      # Reload from saved files
      metadata = JSON.parse(File.read(metadata_path))
      metadata["articles"].map do |article|
        wikitext_path = File.join(@samples_dir, article["wikitext_file"])
        rendered_path = File.join(@samples_dir, article["rendered_file"])

        {
          title: article["title"],
          wikitext: File.read(wikitext_path),
          rendered: File.read(rendered_path)
        }
      end
    end
  end

  def process_with_wp2txt(articles)
    results = []

    articles.each_with_index do |article, idx|
      print "\rProcessing: #{idx + 1}/#{articles.size}..."

      # Process with different configurations
      basic = format_wiki(article[:wikitext], title: article[:title])
      with_templates = format_wiki(article[:wikitext],
                                    title: article[:title],
                                    expand_templates: true)

      results << {
        title: article[:title],
        basic: basic,
        with_templates: with_templates
      }
    end

    puts " done"
    results
  end

  def compare_results(articles, wp2txt_results)
    comparisons = []

    articles.zip(wp2txt_results).each do |article, wp2txt|
      rendered = normalize_text(article[:rendered])
      basic = normalize_text(wp2txt[:basic])
      with_templates = normalize_text(wp2txt[:with_templates])

      # Calculate similarity scores
      basic_similarity = calculate_similarity(rendered, basic)
      templates_similarity = calculate_similarity(rendered, with_templates)

      # Count template patterns in wikitext
      template_count = article[:wikitext].scan(/\{\{[^{}]*\}\}/).size
      parser_func_count = article[:wikitext].scan(/\{\{#[a-z]+:/i).size

      comparisons << {
        title: article[:title],
        wikitext_size: article[:wikitext].size,
        rendered_size: rendered.size,
        template_count: template_count,
        parser_func_count: parser_func_count,
        basic_output_size: basic.size,
        templates_output_size: with_templates.size,
        basic_similarity: basic_similarity,
        templates_similarity: templates_similarity,
        improvement: templates_similarity - basic_similarity
      }

      if @verbose
        puts "\n#{article[:title]}:"
        puts "  Templates: #{template_count}, Parser funcs: #{parser_func_count}"
        puts "  Basic: #{(basic_similarity * 100).round(1)}%"
        puts "  With templates: #{(templates_similarity * 100).round(1)}%"
        puts "  Improvement: #{((templates_similarity - basic_similarity) * 100).round(1)}%"
      end
    end

    comparisons
  end

  def normalize_text(text)
    return "" if text.nil?

    text
      .gsub(/\s+/, " ")           # Normalize whitespace
      .gsub(/\[.*?\]/, "")        # Remove markers like [MATH], [TABLE]
      .gsub(/\n+/, "\n")          # Normalize newlines
      .strip
      .downcase
  end

  def calculate_similarity(reference, candidate)
    return 0.0 if reference.empty? || candidate.empty?

    # Use simple word overlap (Jaccard similarity)
    ref_words = reference.split(/\s+/).to_set
    cand_words = candidate.split(/\s+/).to_set

    return 0.0 if ref_words.empty? && cand_words.empty?
    return 0.0 if ref_words.empty? || cand_words.empty?

    intersection = ref_words & cand_words
    union = ref_words | cand_words

    intersection.size.to_f / union.size
  end

  def generate_report(comparisons)
    FileUtils.mkdir_p(@results_dir)

    # Calculate aggregate statistics
    stats = calculate_statistics(comparisons)

    # Save detailed results as JSON
    json_path = File.join(@results_dir, "detailed_results.json")
    File.write(json_path, JSON.pretty_generate({
      lang: @lang,
      sample_size: comparisons.size,
      generated_at: Time.now.iso8601,
      statistics: stats,
      articles: comparisons
    }))

    # Generate human-readable report
    report_path = File.join(@results_dir, "report.txt")
    File.write(report_path, generate_text_report(stats, comparisons))

    # Print summary
    puts
    puts "=" * 60
    puts "BENCHMARK RESULTS"
    puts "=" * 60
    puts
    puts "Sample size: #{comparisons.size} articles"
    puts "Language: #{@lang}"
    puts
    puts "Average similarity to MediaWiki output:"
    puts "  Basic (no template expansion):  #{(stats[:avg_basic_similarity] * 100).round(1)}%"
    puts "  With template expansion:        #{(stats[:avg_templates_similarity] * 100).round(1)}%"
    puts "  Improvement:                    +#{(stats[:avg_improvement] * 100).round(1)}%"
    puts
    puts "Template statistics:"
    puts "  Total templates found:          #{stats[:total_templates]}"
    puts "  Avg templates per article:      #{stats[:avg_templates_per_article].round(1)}"
    puts "  Total parser functions:         #{stats[:total_parser_funcs]}"
    puts
    puts "Articles with improvement:        #{stats[:articles_with_improvement]}/#{comparisons.size}"
    puts "  (#{(stats[:articles_with_improvement].to_f / comparisons.size * 100).round(1)}%)"
  end

  def calculate_statistics(comparisons)
    {
      avg_basic_similarity: comparisons.map { |c| c[:basic_similarity] }.sum / comparisons.size,
      avg_templates_similarity: comparisons.map { |c| c[:templates_similarity] }.sum / comparisons.size,
      avg_improvement: comparisons.map { |c| c[:improvement] }.sum / comparisons.size,
      total_templates: comparisons.map { |c| c[:template_count] }.sum,
      avg_templates_per_article: comparisons.map { |c| c[:template_count] }.sum.to_f / comparisons.size,
      total_parser_funcs: comparisons.map { |c| c[:parser_func_count] }.sum,
      articles_with_improvement: comparisons.count { |c| c[:improvement] > 0.01 },
      max_improvement: comparisons.map { |c| c[:improvement] }.max,
      min_improvement: comparisons.map { |c| c[:improvement] }.min
    }
  end

  def generate_text_report(stats, comparisons)
    report = []
    report << "Template Expansion Benchmark Report"
    report << "=" * 60
    report << ""
    report << "Generated: #{Time.now}"
    report << "Language: #{@lang}"
    report << "Sample size: #{comparisons.size}"
    report << ""
    report << "AGGREGATE STATISTICS"
    report << "-" * 40
    report << "Average similarity (basic):       #{(stats[:avg_basic_similarity] * 100).round(2)}%"
    report << "Average similarity (templates):   #{(stats[:avg_templates_similarity] * 100).round(2)}%"
    report << "Average improvement:              #{(stats[:avg_improvement] * 100).round(2)}%"
    report << ""
    report << "Total templates in sample:        #{stats[:total_templates]}"
    report << "Total parser functions:           #{stats[:total_parser_funcs]}"
    report << ""
    report << "TOP 10 ARTICLES BY IMPROVEMENT"
    report << "-" * 40

    top_improved = comparisons.sort_by { |c| -c[:improvement] }.first(10)
    top_improved.each_with_index do |c, idx|
      report << "#{idx + 1}. #{c[:title]}"
      report << "   Templates: #{c[:template_count]}, Improvement: +#{(c[:improvement] * 100).round(1)}%"
    end

    report << ""
    report << "BOTTOM 10 ARTICLES (LEAST IMPROVEMENT)"
    report << "-" * 40

    bottom = comparisons.sort_by { |c| c[:improvement] }.first(10)
    bottom.each_with_index do |c, idx|
      report << "#{idx + 1}. #{c[:title]}"
      report << "   Templates: #{c[:template_count]}, Improvement: #{(c[:improvement] * 100).round(1)}%"
    end

    report.join("\n")
  end
end

# Parse command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on("-l", "--lang LANG", "Wikipedia language code (default: en)") do |v|
    options[:lang] = v
  end

  opts.on("-c", "--count N", Integer, "Number of articles to sample (default: 100)") do |v|
    options[:count] = v
  end

  opts.on("-o", "--output DIR", "Output directory (default: benchmark_results)") do |v|
    options[:output_dir] = v
  end

  opts.on("--use-cache", "Use cached samples if available") do
    options[:use_cache] = true
  end

  opts.on("-v", "--verbose", "Show detailed output") do
    options[:verbose] = true
  end

  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end.parse!

# Run benchmark
benchmark = TemplateBenchmark.new(options)
benchmark.run
