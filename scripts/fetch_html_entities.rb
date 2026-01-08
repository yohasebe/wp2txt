# frozen_string_literal: true

# Fetches HTML named character references from WHATWG HTML specification
# Usage: ruby scripts/fetch_html_entities.rb
#
# This script downloads the official entities.json from WHATWG and converts
# it into a format suitable for wp2txt text processing.

require "net/http"
require "json"
require "fileutils"

WHATWG_ENTITIES_URL = "https://html.spec.whatwg.org/entities.json"

def fetch_whatwg_entities
  puts "Fetching entities from WHATWG HTML specification..."
  uri = URI(WHATWG_ENTITIES_URL)

  response = Net::HTTP.get_response(uri)
  unless response.is_a?(Net::HTTPSuccess)
    warn "Failed to fetch entities: HTTP #{response.code}"
    return nil
  end

  JSON.parse(response.body)
rescue StandardError => e
  warn "Error fetching entities: #{e.message}"
  nil
end

def convert_entities(raw_data)
  entities = {}

  raw_data.each do |name, info|
    # Only include entries with semicolon (standard form)
    # Skip legacy forms without semicolon like "&nbsp"
    next unless name.end_with?(";")

    # Extract entity name without & and ;
    # e.g., "&alpha;" -> "alpha"
    key = name

    # Get the character(s)
    characters = info["characters"]
    next if characters.nil? || characters.empty?

    entities[key] = characters
  end

  entities
end

def main
  raw_data = fetch_whatwg_entities
  if raw_data.nil?
    warn "Failed to fetch entities. Aborting."
    exit 1
  end

  puts "Processing #{raw_data.size} raw entries..."

  entities = convert_entities(raw_data)
  puts "Converted to #{entities.size} standard entities (with semicolon)"

  result = {
    "meta" => {
      "generated_at" => Time.now.utc.iso8601,
      "source" => WHATWG_ENTITIES_URL,
      "description" => "HTML named character references from WHATWG HTML specification",
      "total_entities" => entities.size
    },
    "entities" => entities.sort.to_h
  }

  # Write output
  output_path = File.join(__dir__, "..", "lib", "wp2txt", "data", "html_entities.json")
  FileUtils.mkdir_p(File.dirname(output_path))

  File.write(output_path, JSON.pretty_generate(result))
  puts "\nData written to: #{output_path}"

  # Summary - show some categories
  greek = entities.keys.select { |k| k.match?(/&(alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|omicron|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega);/i) }
  math = entities.keys.select { |k| k.match?(/&(sum|prod|int|infin|nabla|part|forall|exist|empty|isin|notin|cap|cup|sub|sup|oplus|otimes);/i) }
  arrows = entities.keys.select { |k| k.match?(/arr;$/i) }

  puts "\n=== Summary ==="
  puts "Total entities: #{entities.size}"
  puts "Greek letters: #{greek.size}"
  puts "Math symbols: #{math.size}"
  puts "Arrows: #{arrows.size}"
end

main if __FILE__ == $PROGRAM_NAME
