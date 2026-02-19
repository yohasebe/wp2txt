# frozen_string_literal: true

# Fetches template aliases and redirects from Wikipedia APIs
# Usage: ruby scripts/fetch_template_data.rb
#
# This script augments the existing template_aliases.json by:
# - Fetching redirects for known templates (to discover aliases)
# - Validating that templates exist
# - Merging new aliases from multiple Wikipedia language editions
#
# Note: Unlike magic words and namespaces (which come from MediaWiki siteinfo),
# templates are wiki-specific pages. This script queries a subset of major
# Wikipedia editions to collect common template aliases.

require "net/http"
require "json"
require "fileutils"
require "set"

# Languages to query for template data
TEMPLATE_LANGUAGES = %w[en ja de fr es it ru zh pt nl pl ar ko].freeze

# Base template names to look up redirects for (English)
# These are canonical names; we'll find their translations and aliases
BASE_TEMPLATES = {
  "remove_templates" => %w[
    Reflist Notelist Sfn Efn Main See_also Further About Portal
  ],
  "authority_control" => %w[
    Authority_control Normdaten Persondata
  ],
  "citation_templates" => %w[
    Cite_web Cite_book Cite_news Cite_journal Citation
  ],
  "sister_project_templates" => %w[
    Commons Commons_category Wiktionary Wikiquote Wikisource
  ]
}.freeze

# Fetch template redirects from a specific Wikipedia
def fetch_template_redirects(lang, template_name)
  uri = URI("https://#{lang}.wikipedia.org/w/api.php")
  params = {
    action: "query",
    titles: "Template:#{template_name}",
    prop: "redirects",
    rdlimit: "max",
    format: "json"
  }
  uri.query = URI.encode_www_form(params)

  response = Net::HTTP.get_response(uri)
  return [] unless response.is_a?(Net::HTTPSuccess)

  data = JSON.parse(response.body)
  pages = data.dig("query", "pages") || {}

  redirects = []
  pages.each_value do |page|
    next if page["missing"]

    # Add the page title itself (normalized)
    page_title = page["title"]&.sub(/^Template:/, "")
    redirects << page_title if page_title

    # Add all redirects
    (page["redirects"] || []).each do |rd|
      rd_title = rd["title"]&.sub(/^Template:/, "")
      redirects << rd_title if rd_title
    end
  end

  redirects.compact.uniq
rescue StandardError => e
  warn "  Error fetching #{lang}:Template:#{template_name}: #{e.message}"
  []
end

# Fetch all templates in a category
def fetch_category_members(lang, category_name, limit: 100)
  uri = URI("https://#{lang}.wikipedia.org/w/api.php")
  params = {
    action: "query",
    list: "categorymembers",
    cmtitle: "Category:#{category_name}",
    cmtype: "page",
    cmnamespace: "10",  # Template namespace
    cmlimit: limit.to_s,
    format: "json"
  }
  uri.query = URI.encode_www_form(params)

  response = Net::HTTP.get_response(uri)
  return [] unless response.is_a?(Net::HTTPSuccess)

  data = JSON.parse(response.body)
  members = data.dig("query", "categorymembers") || []

  members.map { |m| m["title"]&.sub(/^Template:/, "") }.compact
rescue StandardError => e
  warn "  Error fetching category #{category_name}: #{e.message}"
  []
end

def main
  puts "Template Data Fetcher"
  puts "=" * 50

  # Load existing data
  data_path = File.join(__dir__, "..", "lib", "wp2txt", "data", "template_aliases.json")
  existing_data = if File.exist?(data_path)
    JSON.parse(File.read(data_path))
  else
    { "meta" => {} }
  end

  # Convert arrays to sets for efficient merging
  categories = {}
  existing_data.each do |key, value|
    next if key == "meta"
    categories[key] = Set.new(value) if value.is_a?(Array)
  end

  puts "\nFetching template redirects from #{TEMPLATE_LANGUAGES.size} Wikipedia editions..."

  # Fetch redirects for base templates
  BASE_TEMPLATES.each do |category, templates|
    puts "\n#{category}:"
    templates.each do |template|
      TEMPLATE_LANGUAGES.each do |lang|
        print "  #{lang}:#{template}..."
        aliases = fetch_template_redirects(lang, template)
        if aliases.any?
          categories[category] ||= Set.new
          aliases.each { |a| categories[category] << a }
          puts " #{aliases.size} aliases"
        else
          puts " not found"
        end
        sleep 0.1  # Rate limiting
      end
    end
  end

  # Fetch citation templates from category (English)
  puts "\nFetching citation templates from category..."
  citation_members = fetch_category_members("en", "Citation templates")
  if citation_members.any?
    categories["citation_templates"] ||= Set.new
    citation_members.each { |t| categories["citation_templates"] << t }
    puts "  Found #{citation_members.size} citation templates"
  end

  # Fetch hatnote templates
  puts "\nFetching hatnote templates from category..."
  hatnote_members = fetch_category_members("en", "Hatnote templates")
  if hatnote_members.any?
    categories["remove_templates"] ||= Set.new
    hatnote_members.each { |t| categories["remove_templates"] << t }
    puts "  Found #{hatnote_members.size} hatnote templates"
  end

  # Convert sets back to sorted arrays
  result = { "meta" => existing_data["meta"] || {} }
  result["meta"]["generated_at"] = Time.now.utc.iso8601
  result["meta"]["source"] = "Manual curation + MediaWiki API (templates)"
  result["meta"]["languages_queried"] = TEMPLATE_LANGUAGES

  categories.each do |key, set|
    result[key] = set.to_a.sort_by(&:downcase)
  end

  # Write output
  File.write(data_path, JSON.pretty_generate(result))
  puts "\n" + "=" * 50
  puts "Data written to: #{data_path}"

  # Summary
  puts "\n=== Summary ==="
  result.each do |key, value|
    next if key == "meta"
    puts "  #{key}: #{value.size} templates"
  end
end

main if __FILE__ == $PROGRAM_NAME
