# frozen_string_literal: true

require_relative "constants"
require_relative "regex"

module Wp2txt
  # Text processing utilities: character conversion, nested structure handling, cleanup

  # Cache for dynamically generated regex patterns
  @regex_cache = {}
  class << self
    attr_accessor :regex_cache
  end

  def convert_characters(text, _has_retried = false)
    # Use scrub to safely handle invalid byte sequences
    text = text.to_s.scrub("")
    text = chrref_to_utf(text)
    text = special_chr(text)
    text.encode("UTF-8", "UTF-8", invalid: :replace, replace: "")
  rescue ::Encoding::InvalidByteSequenceError, ::Encoding::UndefinedConversionError, ArgumentError
    # If any encoding error persists, scrub again and return
    text.to_s.scrub("")
  end

  def special_chr(str)
    result = HTML_DECODER.decode(str)
    # Decode additional mathematical entities not covered by HTMLEntities gem
    result.gsub!(MATH_ENTITIES_REGEX) { MATH_ENTITIES[$1] }
    result
  end

  def chrref_to_utf(num_str)
    num_str.gsub(CHRREF_TO_UTF_REGEX) do
      codepoint = $1 == "x" ? $2.to_i(16) : $2.to_i
      # Handle all valid Unicode codepoints (U+0001 to U+10FFFF)
      if codepoint > 0 && codepoint <= 0x10FFFF
        [codepoint].pack("U")
      else
        ""
      end
    end
  rescue RangeError, ArgumentError
    # RangeError: invalid codepoint, ArgumentError: pack error
    num_str
  end

  def mndash(str)
    str.gsub(MNDASH_REGEX, "–")
  end

  #################### parser for nested structure ####################

  # Optimized single-pass nested structure processor
  # Processes innermost brackets first, avoiding recursion overhead
  def process_nested_structure(scanner, left, right, &block)
    str = scanner.is_a?(StringScanner) ? scanner.string : scanner.to_s
    process_nested_single_pass(str, left, right, &block)
  end

  # Single-pass iterative processor - finds and processes innermost brackets first
  # This avoids the overhead of recursive calls and repeated string scanning
  def process_nested_single_pass(str, left, right, &block)
    return str unless str.include?(left)

    result = +str
    left_len = left.length
    right_len = right.length
    max_iterations = MAX_NESTING_ITERATIONS

    iterations = 0
    loop do
      iterations += 1
      break if iterations > max_iterations

      pos = 0
      found = false

      while pos < result.length
        # Find next left bracket
        left_pos = result.index(left, pos)
        break unless left_pos

        # Look for nested left bracket and matching right bracket
        inner_left = result.index(left, left_pos + left_len)
        right_pos = result.index(right, left_pos + left_len)

        break unless right_pos

        # If there's a nested left bracket before the right, skip to process inner first
        if inner_left && inner_left < right_pos
          pos = inner_left
          next
        end

        # Found innermost pair - process it
        content = result[(left_pos + left_len)...right_pos]
        processed = yield content
        result = result[0...left_pos] + processed + result[(right_pos + right_len)..]
        found = true
        break
      end

      break unless found
    end

    result
  rescue RegexpError, ArgumentError, SystemStackError
    # RegexpError: malformed pattern, ArgumentError: invalid argument
    # SystemStackError: stack overflow from deeply nested content
    str
  end

  #################### nowiki handling ####################

  def escape_nowiki(str)
    if @nowikis
      @nowikis.clear
    else
      @nowikis = {}
    end
    str.gsub(ESCAPE_NOWIKI_REGEX) do
      nowiki = $1
      nowiki_id = nowiki.object_id
      @nowikis[nowiki_id] = nowiki
      "<nowiki-#{nowiki_id}>"
    end
  end

  def unescape_nowiki(str)
    str.gsub(UNESCAPE_NOWIKI_REGEX) do
      obj_id = $1.to_i
      @nowikis[obj_id]
    end
  end

  #################### cleanup and removal methods ####################

  def cleanup(text)
    # Work with a mutable copy to reduce intermediate string allocations
    result = +text.to_s
    result.gsub!(CLEANUP_REGEX_01, "")
    result.gsub!(CLEANUP_REGEX_02, "")
    result.gsub!(CLEANUP_REGEX_03, "")
    result.gsub!(CLEANUP_REGEX_04, "")
    result.gsub!(CLEANUP_REGEX_05, "")
    result.gsub!(CLEANUP_REGEX_06, "")
    result.gsub!(CLEANUP_REGEX_07, "")
    # Reduce 3+ consecutive newlines to 2
    result.gsub!(CLEANUP_REGEX_08, "\n\n")
    # Also handle mixed whitespace patterns (spaces/tabs between newlines)
    result.gsub!(/\n[ \t]*\n[ \t]*\n+/, "\n\n")

    # Fix 1: Multiple consecutive spaces → single space (but preserve indentation at line start)
    result.gsub!(/([^\n]) {2,}/, '\1 ')

    # Fix 2: Empty parentheses → remove (both ASCII and Japanese)
    result.gsub!(/\(\s*\)/, "")
    result.gsub!(/（\s*）/, "")

    # Fix 3: Leftover pipe characters (table/infobox remnants)
    result.gsub!(/\|\|+/, "")           # Multiple pipes
    result.gsub!(/\|\s*$/, "")          # Trailing pipe at end of line
    result.gsub!(/^\s*\|[^|]*$\n?/m, "") # Lines that are just pipe + content (table rows)
    # Lines with multiple pipe-separated key=value pairs (infobox remnants)
    result.gsub!(/^\s*\|?\w+=[\w\s-]+(?:\|\w+=[\w\s-]+)+\s*$/m, "")
    # Template name remnants (data-driven from template_aliases.json)
    result.gsub!(CLEANUP_REMNANTS_REGEX, "")
    # Imagemap/gallery remnants: lines like "Image:file.jpg|thumb|...|caption" without [[ brackets
    result.gsub!(CLEANUP_FILE_LINE_REGEX, "")
    # Incomplete File/Image links (opened but not closed on same logical unit)
    result.gsub!(CLEANUP_FILE_INCOMPLETE_REGEX, "")
    # Orphaned closing brackets from split File links (e.g., "caption]] rest of text")
    # Only match ]] at start of line or preceded by whitespace (not part of [[...]])
    result.gsub!(/(?:^|(?<=\s))([^|\[\]\n]+)\]\]/, '\1')
    # Orphaned opening wiki brackets not closed on same line
    # Only match [[ followed by non-bracket, non-newline chars until end of line
    result.gsub!(/\[\[[^\[\]\n]*$/, "")
    # Standalone ]] on its own line (broken/incomplete links from Wikipedia source)
    result.gsub!(/^\s*\]\]\s*$/m, "")
    # ]] preceded by pipe without matching [[ (orphaned from broken links)
    # Only match if NOT immediately preceded by [[  (to protect valid links)
    # Pattern: non-bracket char + pipe + text + ]] (where the preceding char proves no [[ nearby)
    result.gsub!(/([^|\[\]\n])\|([^|\[\]\n]+)\]\](?!\])/) { "#{$1}#{$2}" }

    # =========================================================================
    # Multilingual cleanup (language-agnostic patterns)
    # =========================================================================

    # MediaWiki magic words: DEFAULTSORT:..., DISPLAYTITLE:...
    # Handles both bare format (DEFAULTSORT:value) and template format ({{DEFAULTSORT:value}})
    result.gsub!(MAGIC_WORD_TEMPLATE_REGEX, "")
    result.gsub!(MAGIC_WORD_LINE_REGEX, "")

    # Double-underscore magic words: __NOTOC__, __TOC__, __FORCETOC__, etc.
    result.gsub!(DOUBLE_UNDERSCORE_MAGIC_REGEX, "")

    # Interwiki links: :en:Article → Article (keep article name, remove prefix)
    result.gsub!(INTERWIKI_PREFIX_REGEX, "")

    # Authority control templates: Normdaten, Authority control, Persondata, etc.
    result.gsub!(AUTHORITY_CONTROL_REGEX, "")

    # Category lines in various languages (but NOT "CATEGORIES:" summary line)
    result.gsub!(CATEGORY_LINE_REGEX, "")

    # Wikimedia sister project markers: Wikibooks, Commons, School:..., etc.
    result.gsub!(WIKIMEDIA_PROJECT_REGEX, "")

    # Lone asterisk lines (list markers without content)
    result.gsub!(LONE_ASTERISK_REGEX, "")

    # Final cleanup: reduce multiple blank lines again after all removals
    result.gsub!(/\n{3,}/, "\n\n")

    result.strip!
    result << "\n\n"
  end

  # Extension tags to remove (block-level tags that should be stripped)
  # Data source: mediawiki_aliases.json (extension_tags)
  # These are MediaWiki extension tags like <gallery>, <timeline>, <imagemap>, etc.
  EXTENSION_TAGS = Wp2txt.load_mediawiki_data["extension_tags"] || []

  # Block-level extension tags to process in remove_html
  # Not all extension tags should be removed here - some are handled by markers (math, chem, etc.)
  # and some are inline (ref). We only remove block-level content containers.
  BLOCK_EXTENSION_TAGS = %w[div gallery timeline noinclude imagemap poem hiero graph categorytree section].freeze

  def remove_html(str)
    res = +str.to_s
    # Remove HTML comments first (before other processing to avoid [ref] in comments issue)
    res.gsub!(HTML_COMMENT_REGEX, "")
    res.gsub!(SELF_CLOSING_TAG_REGEX, "")

    # Use data-driven extension tags, filtered to block-level only
    # Combine BLOCK_EXTENSION_TAGS with extension_tags from data for comprehensive coverage
    tags_to_remove = (BLOCK_EXTENSION_TAGS + EXTENSION_TAGS.select { |t|
      # Include additional block-level tags from data
      %w[div gallery timeline noinclude imagemap poem hiero graph categorytree section abschnitt].include?(t)
    }).uniq

    tags_to_remove.each do |tag|
      # Early exit if tag not present
      next unless res.include?("<#{tag}")
      result = process_nested_single_pass(res, "<#{tag}", "#{tag}>") { "" }
      res.replace(result)
    end
    # Remove imagemap coordinate remnants (rect, poly, circle, default with coordinates)
    res.gsub!(/^(?:rect|poly|circle|default)\s+[\d\s]+.*$/i, "")
    res
  end

  def remove_complex(str)
    # Work with a mutable copy to reduce intermediate string allocations
    result = +str.to_s
    result.gsub!(COMPLEX_REGEX_01) { "《#{$1}》" }
    result.gsub!(COMPLEX_REGEX_02, "")
    result.gsub!(COMPLEX_REGEX_03, "")
    result.gsub!(COMPLEX_REGEX_04, "")
    result.gsub!(COMPLEX_REGEX_05, "")
    result
  end

  def remove_inbetween(str, tagset = ["<", ">"])
    # Use cached regex for common tagsets
    cache_key = "inbetween:#{tagset.join}"
    regex = Wp2txt.regex_cache[cache_key] ||= begin
      tagsets = Regexp.quote(tagset.uniq.join(""))
      Regexp.new("#{Regexp.escape(tagset[0])}[^#{tagsets}]*#{Regexp.escape(tagset[1])}")
    end
    str.gsub(regex, "")
  end

  def remove_tag(str)
    str.gsub(REMOVE_TAG_REGEX, "")
  end

  def remove_directive(str)
    str.gsub(REMOVE_DIRECTIVES_REGEX, "")
  end

  def remove_emphasis(str)
    str.gsub(REMOVE_EMPHASIS_REGEX) do
      $2
    end
  end

  def remove_hr(str)
    str.gsub(REMOVE_HR_REGEX, "")
  end

  def remove_ref(str)
    str.gsub(FORMAT_REF_REGEX) { "" }
  end

  def make_reference(str)
    # Work with a mutable copy to reduce intermediate string allocations
    result = +str.to_s
    result.gsub!(MAKE_REFERENCE_REGEX_A, "\n")
    result.gsub!(MAKE_REFERENCE_REGEX_B, "")
    result.gsub!(MAKE_REFERENCE_REGEX_C, "[ref]")
    result.gsub!(MAKE_REFERENCE_REGEX_D, "[/ref]")
    result
  end
end
