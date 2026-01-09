# frozen_string_literal: true

# Fetches magic words, namespace data, and interwiki info from Wikipedia APIs
# Usage: ruby scripts/fetch_mediawiki_data.rb
#
# This script queries the MediaWiki API for all Wikipedia language editions
# and extracts:
# - Magic words (redirect, defaultsort, displaytitle, image options, etc.)
# - Double-underscore behavior switches (__NOTOC__, __TOC__, etc.)
# - Namespace names and aliases (Category, File, Template, etc.)
# - Interwiki map (for sister projects)

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

# All namespace IDs (negative = special, 0 = main article, positive = other)
# We want to collect all non-article namespaces for filtering
# ID 0 is main namespace (articles), we want everything else
NON_ARTICLE_NAMESPACE_IDS = [
  -2,  # Media
  -1,  # Special
  # 0 is main article namespace - skip
  1,   # Talk
  2,   # User
  3,   # User talk
  4,   # Project (Wikipedia)
  5,   # Project talk
  6,   # File
  7,   # File talk
  8,   # MediaWiki
  9,   # MediaWiki talk
  10,  # Template
  11,  # Template talk
  12,  # Help
  13,  # Help talk
  14,  # Category
  15,  # Category talk
  # 100+ are custom namespaces per wiki (Portal, WikiProject, Module, etc.)
].freeze

# We still need specific namespace collections for targeted operations
SPECIFIC_NAMESPACE_IDS = {
  "file" => 6,
  "category" => 14,
  "template" => 10,
  "wikipedia" => 4,
  "help" => 12,
  "portal" => 100, # May not exist in all wikis
  "module" => 828  # May not exist in all wikis
}.freeze

def fetch_siteinfo(lang)
  uri = URI("https://#{lang}.wikipedia.org/w/api.php")
  params = {
    action: "query",
    meta: "siteinfo",
    siprop: "magicwords|namespaces|namespacealiases|interwikimap|extensiontags",
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

def extract_extension_tags(data)
  return [] unless data&.dig("query", "extensiontags")

  # Extension tags come as ["<tag>", ...], extract just the tag name
  data["query"]["extensiontags"].map do |tag|
    tag.gsub(/^<|>$/, "")
  end.compact.uniq
end

def extract_magic_words(data)
  return {} unless data&.dig("query", "magicwords")

  result = {}
  double_underscore = []

  data["query"]["magicwords"].each do |mw|
    name = mw["name"]
    aliases = mw["aliases"] || []

    # Collect double-underscore magic words (behavior switches)
    double_underscore_aliases = aliases.select { |a| a.start_with?("__") && a.end_with?("__") }
    double_underscore.concat(double_underscore_aliases) unless double_underscore_aliases.empty?

    # Only keep specific magic words we care about
    next unless RELEVANT_MAGIC_WORDS.include?(name)

    # Remove # prefix for redirect (we'll add it in regex)
    if name == "redirect"
      aliases = aliases.map { |a| a.sub(/^[#＃]/, "") }
    end
    result[name] = aliases.uniq
  end

  # Add double-underscore as a special category
  result["double_underscore"] = double_underscore.uniq unless double_underscore.empty?

  result
end

def extract_namespaces(data)
  return {} unless data&.dig("query", "namespaces")

  result = {}
  all_non_article = []

  # Get main namespace names
  data["query"]["namespaces"].each do |id, ns|
    id_int = id.to_i

    # Collect all non-article namespace names
    if id_int != 0 && ns["*"] && !ns["*"].empty?
      all_non_article << ns["*"]
      all_non_article << ns["canonical"] if ns["canonical"] && !ns["canonical"].empty?
    end

    # Also collect specific namespaces by ID
    SPECIFIC_NAMESPACE_IDS.each do |key, target_id|
      next unless id_int == target_id

      result[key] ||= []
      result[key] << ns["canonical"] if ns["canonical"] && !ns["canonical"].empty?
      result[key] << ns["*"] if ns["*"] && !ns["*"].empty? && ns["*"] != ns["canonical"]
    end
  end

  # Get namespace aliases
  (data["query"]["namespacealiases"] || []).each do |alias_info|
    id = alias_info["id"]
    alias_name = alias_info["*"]
    next unless alias_name && !alias_name.empty?

    # Add to all non-article namespaces
    all_non_article << alias_name if id != 0

    # Add to specific namespace collections
    SPECIFIC_NAMESPACE_IDS.each do |key, target_id|
      next unless id == target_id

      result[key] ||= []
      result[key] << alias_name
    end
  end

  # Store all non-article namespace names
  result["non_article"] = all_non_article.uniq

  # Deduplicate all collections
  result.transform_values!(&:uniq)
  result
end

def extract_interwiki(data)
  return {} unless data&.dig("query", "interwikimap")

  result = {}
  sister_projects = []

  # Known Wikimedia sister project prefixes
  wikimedia_projects = %w[
    commons wikibooks wikinews wikiquote wikisource
    wikiversity wikivoyage wiktionary wikidata wikispecies
    meta mediawiki mediawikiwiki species
  ]

  data["query"]["interwikimap"].each do |iw|
    prefix = iw["prefix"]
    url = iw["url"] || ""

    # Check if this is a Wikimedia project
    is_wikimedia = wikimedia_projects.include?(prefix) ||
                   url.include?("wikimedia.org") ||
                   url.include?("wikipedia.org") ||
                   url.include?("wikibooks.org") ||
                   url.include?("wikinews.org") ||
                   url.include?("wikiquote.org") ||
                   url.include?("wikisource.org") ||
                   url.include?("wikiversity.org") ||
                   url.include?("wikivoyage.org") ||
                   url.include?("wiktionary.org") ||
                   url.include?("wikidata.org") ||
                   url.include?("wikispecies.org") ||
                   url.include?("mediawiki.org")

    sister_projects << prefix if is_wikimedia
  end

  result["sister_projects"] = sister_projects.uniq
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
  all_interwiki = Hash.new { |h, k| h[k] = Set.new }
  all_extension_tags = Set.new
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

    # Merge interwiki
    extract_interwiki(data).each do |name, prefixes|
      prefixes.each { |p| all_interwiki[name] << p }
    end

    # Merge extension tags (consistent across all wikis, but collect from all to be safe)
    extract_extension_tags(data).each { |tag| all_extension_tags << tag }

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
    "namespaces" => all_namespaces.transform_values { |v| v.to_a.sort },
    "interwiki" => all_interwiki.transform_values { |v| v.to_a.sort },
    "extension_tags" => all_extension_tags.to_a.sort
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
  puts "\nInterwiki:"
  result["interwiki"].each do |name, prefixes|
    puts "  #{name}: #{prefixes.size} prefixes"
  end
  puts "\nExtension Tags: #{result["extension_tags"].size} tags"
end

main if __FILE__ == $PROGRAM_NAME
