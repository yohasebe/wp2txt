# frozen_string_literal: true

# Fetches magic words and namespace data from Wikipedia APIs
# Usage: ruby scripts/fetch_mediawiki_data.rb
#
# This script queries the MediaWiki API for all Wikipedia language editions
# and extracts magic words (redirect, image options, etc.) and namespace
# aliases (Category, File, etc.) to create a consolidated data file.

require "net/http"
require "json"
require "fileutils"

# Fetch all Wikipedia language codes from Wikimedia sitematrix API
def fetch_all_wikipedia_languages
  uri = URI("https://meta.wikimedia.org/w/api.php")
  params = {
    action: "sitematrix",
    smtype: "language",
    format: "json"
  }
  uri.query = URI.encode_www_form(params)

  response = Net::HTTP.get_response(uri)
  return [] unless response.is_a?(Net::HTTPSuccess)

  data = JSON.parse(response.body)
  languages = []

  data["sitematrix"].each do |key, val|
    next unless key.match?(/^\d+$/) && val.is_a?(Hash) && val["site"]

    # Check if this language has a Wikipedia (code: 'wiki')
    has_wikipedia = val["site"].any? { |site| site["code"] == "wiki" }
    languages << val["code"] if has_wikipedia
  end

  languages.sort
rescue StandardError => e
  warn "Error fetching language list: #{e.message}"
  []
end

# Magic word types we care about for text processing
RELEVANT_MAGIC_WORDS = %w[
  redirect
  notoc noeditsection nogallery forcetoc toc nocontentconvert nocc
  notitleconvert notc displaytitle defaultsort
  img_thumbnail img_manualthumb img_right img_left img_none img_center
  img_framed img_frameless img_page img_upright img_border img_baseline
  img_sub img_super img_top img_text_top img_middle img_bottom img_text_bottom
  img_link img_alt img_class img_lang
].freeze

# Namespace IDs we care about
# 6 = File, 14 = Category
RELEVANT_NAMESPACE_IDS = [6, 14].freeze

def fetch_siteinfo(lang)
  uri = URI("https://#{lang}.wikipedia.org/w/api.php")
  params = {
    action: "query",
    meta: "siteinfo",
    siprop: "magicwords|namespaces|namespacealiases",
    format: "json"
  }
  uri.query = URI.encode_www_form(params)

  response = Net::HTTP.get_response(uri)
  return nil unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
rescue StandardError => e
  warn "  Error fetching #{lang}: #{e.message}"
  nil
end

def extract_magic_words(data)
  return {} unless data&.dig("query", "magicwords")

  result = {}
  data["query"]["magicwords"].each do |mw|
    name = mw["name"]
    next unless RELEVANT_MAGIC_WORDS.include?(name)

    aliases = mw["aliases"] || []
    # Remove # prefix for redirect (we'll add it in regex)
    if name == "redirect"
      aliases = aliases.map { |a| a.sub(/^[#＃]/, "") }
    end
    result[name] = aliases.uniq
  end
  result
end

def extract_namespaces(data)
  return {} unless data&.dig("query", "namespaces")

  result = {}

  # Get main namespace names
  data["query"]["namespaces"].each do |id, ns|
    id_int = id.to_i
    next unless RELEVANT_NAMESPACE_IDS.include?(id_int)

    key = id_int == 6 ? "file" : "category"
    result[key] ||= []
    result[key] << ns["canonical"] if ns["canonical"]
    result[key] << ns["*"] if ns["*"] && ns["*"] != ns["canonical"]
  end

  # Get namespace aliases
  (data["query"]["namespacealiases"] || []).each do |alias_info|
    id = alias_info["id"]
    next unless RELEVANT_NAMESPACE_IDS.include?(id)

    key = id == 6 ? "file" : "category"
    result[key] ||= []
    result[key] << alias_info["*"] if alias_info["*"]
  end

  # Deduplicate
  result.transform_values!(&:uniq)
  result
end

def main
  puts "Fetching list of all Wikipedia languages..."
  languages = fetch_all_wikipedia_languages

  if languages.empty?
    warn "Failed to fetch language list. Aborting."
    exit 1
  end

  puts "Found #{languages.size} Wikipedia editions. Fetching data..."

  all_magic_words = Hash.new { |h, k| h[k] = Set.new }
  all_namespaces = Hash.new { |h, k| h[k] = Set.new }
  successful = 0
  failed = []

  languages.each_with_index do |lang, idx|
    print "\r  Processing: #{lang.ljust(10)} (#{idx + 1}/#{languages.size})"
    $stdout.flush

    data = fetch_siteinfo(lang)
    unless data
      failed << lang
      next
    end

    # Merge magic words
    extract_magic_words(data).each do |name, aliases|
      aliases.each { |a| all_magic_words[name] << a }
    end

    # Merge namespaces
    extract_namespaces(data).each do |name, aliases|
      aliases.each { |a| all_namespaces[name] << a }
    end

    successful += 1
    sleep 0.05 # Rate limiting (faster since we have many languages)
  end

  puts "\n  Successfully fetched: #{successful}/#{languages.size}"
  puts "  Failed: #{failed.size} (#{failed.first(10).join(', ')}#{failed.size > 10 ? '...' : ''})" if failed.any?

  # Convert Sets to sorted Arrays
  result = {
    "meta" => {
      "generated_at" => Time.now.utc.iso8601,
      "source" => "MediaWiki API (siteinfo via Wikimedia sitematrix)",
      "languages_queried" => languages.size,
      "languages_successful" => successful
    },
    "magic_words" => all_magic_words.transform_values { |v| v.to_a.sort },
    "namespaces" => all_namespaces.transform_values { |v| v.to_a.sort }
  }

  # Write output
  output_path = File.join(__dir__, "..", "lib", "wp2txt", "data", "mediawiki_aliases.json")
  FileUtils.mkdir_p(File.dirname(output_path))

  File.write(output_path, JSON.pretty_generate(result))
  puts "\nData written to: #{output_path}"

  # Summary
  puts "\n=== Summary ==="
  puts "Magic Words:"
  result["magic_words"].each do |name, aliases|
    puts "  #{name}: #{aliases.size} aliases"
  end
  puts "\nNamespaces:"
  result["namespaces"].each do |name, aliases|
    puts "  #{name}: #{aliases.size} aliases"
  end
end

main if __FILE__ == $PROGRAM_NAME
