# frozen_string_literal: true

# Fetches Wikipedia language metadata from Wikimedia APIs
# Usage: ruby scripts/fetch_language_metadata.rb
#
# This script queries the Wikimedia sitematrix API to get all Wikipedia
# language editions and their statistics (article counts, etc.)

require "net/http"
require "json"
require "fileutils"

# Fetch all Wikipedia languages with statistics from sitematrix API
def fetch_wikipedia_languages
  uri = URI("https://meta.wikimedia.org/w/api.php")
  params = {
    action: "sitematrix",
    smtype: "language",
    format: "json"
  }
  uri.query = URI.encode_www_form(params)

  response = Net::HTTP.get_response(uri)
  return {} unless response.is_a?(Net::HTTPSuccess)

  data = JSON.parse(response.body)
  languages = {}

  data["sitematrix"].each do |key, val|
    next unless key.match?(/^\d+$/) && val.is_a?(Hash) && val["site"]

    # Find Wikipedia site info
    wiki_site = val["site"].find { |site| site["code"] == "wiki" }
    next unless wiki_site

    lang_code = val["code"]
    languages[lang_code] = {
      "name" => val["name"],
      "localname" => val["localname"],
      "url" => wiki_site["url"],
      "dbname" => wiki_site["dbname"],
      "closed" => wiki_site["closed"] || false,
      "private" => wiki_site["private"] || false
    }
  end

  languages
rescue StandardError => e
  warn "Error fetching sitematrix: #{e.message}"
  {}
end

# Fetch article statistics for a specific Wikipedia
def fetch_wiki_statistics(lang_code)
  uri = URI("https://#{lang_code}.wikipedia.org/w/api.php")
  params = {
    action: "query",
    meta: "siteinfo",
    siprop: "statistics",
    format: "json"
  }
  uri.query = URI.encode_www_form(params)

  response = Net::HTTP.get_response(uri)
  return nil unless response.is_a?(Net::HTTPSuccess)

  data = JSON.parse(response.body)
  stats = data.dig("query", "statistics")
  return nil unless stats

  {
    "articles" => stats["articles"],
    "pages" => stats["pages"],
    "edits" => stats["edits"],
    "users" => stats["users"],
    "activeusers" => stats["activeusers"]
  }
rescue StandardError
  nil
end

def main
  puts "Fetching Wikipedia language list..."
  languages = fetch_wikipedia_languages

  if languages.empty?
    warn "Failed to fetch language list. Aborting."
    exit 1
  end

  # Filter out closed/private wikis
  active_languages = languages.reject { |_, info| info["closed"] || info["private"] }
  puts "Found #{active_languages.size} active Wikipedia editions."

  puts "Fetching statistics for each Wikipedia (this may take a few minutes)..."
  successful = 0
  failed = []

  active_languages.each_with_index do |(lang_code, info), idx|
    print "\r  Processing: #{lang_code.ljust(10)} (#{idx + 1}/#{active_languages.size})"
    $stdout.flush

    stats = fetch_wiki_statistics(lang_code)
    if stats
      info.merge!(stats)
      successful += 1
    else
      failed << lang_code
    end

    sleep 0.05 # Rate limiting
  end

  puts "\n  Successfully fetched: #{successful}/#{active_languages.size}"
  puts "  Failed: #{failed.size} (#{failed.first(10).join(', ')}#{failed.size > 10 ? '...' : ''})" if failed.any?

  # Categorize by size
  size_categories = {
    "large" => [],    # 1M+ articles
    "medium" => [],   # 100K-1M articles
    "small" => [],    # 10K-100K articles
    "mini" => []      # <10K articles
  }

  active_languages.each do |lang_code, info|
    articles = info["articles"] || 0
    category = if articles >= 1_000_000
                 "large"
               elsif articles >= 100_000
                 "medium"
               elsif articles >= 10_000
                 "small"
               else
                 "mini"
               end
    size_categories[category] << lang_code
    info["size_category"] = category
  end

  # Build result
  result = {
    "meta" => {
      "generated_at" => Time.now.utc.iso8601,
      "source" => "Wikimedia sitematrix + siteinfo APIs",
      "total_languages" => active_languages.size,
      "statistics_fetched" => successful
    },
    "size_summary" => {
      "large" => size_categories["large"].size,
      "medium" => size_categories["medium"].size,
      "small" => size_categories["small"].size,
      "mini" => size_categories["mini"].size
    },
    "languages" => active_languages.sort_by { |_, info| -(info["articles"] || 0) }.to_h
  }

  # Write output
  output_path = File.join(__dir__, "..", "lib", "wp2txt", "data", "language_metadata.json")
  FileUtils.mkdir_p(File.dirname(output_path))

  File.write(output_path, JSON.pretty_generate(result))
  puts "\nData written to: #{output_path}"

  # Summary
  puts "\n=== Summary ==="
  puts "Total active Wikipedias: #{active_languages.size}"
  puts "Size categories:"
  puts "  Large (1M+ articles): #{size_categories['large'].size} - #{size_categories['large'].first(5).join(', ')}..."
  puts "  Medium (100K-1M): #{size_categories['medium'].size}"
  puts "  Small (10K-100K): #{size_categories['small'].size}"
  puts "  Mini (<10K): #{size_categories['mini'].size}"

  # Top 20 by article count
  puts "\nTop 20 Wikipedias by article count:"
  active_languages.sort_by { |_, info| -(info["articles"] || 0) }.first(20).each_with_index do |(code, info), idx|
    puts "  #{(idx + 1).to_s.rjust(2)}. #{code.ljust(5)} #{info['name'].to_s.ljust(20)} #{(info['articles'] || 0).to_s.rjust(10)} articles"
  end
end

main if __FILE__ == $PROGRAM_NAME
