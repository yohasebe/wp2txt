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

  # Get HTML decoder instance (thread-local for Ractor compatibility)
  def html_decoder
    Thread.current[:wp2txt_html_decoder] ||= HTMLEntities.new
  end

  def special_chr(str)
    result = html_decoder.decode(str)
    # Decode additional mathematical entities not covered by HTMLEntities gem
    result.gsub!(MATH_ENTITIES_REGEX) { MATH_ENTITIES[$1] }
    result
  rescue RangeError
    # RangeError: character code out of range (e.g., invalid numeric entity like &#1550315;)
    # Remove invalid numeric entities and try again
    cleaned = str.gsub(/&#(\d+);/) do |match|
      codepoint = $1.to_i
      codepoint <= 0x10FFFF ? match : ""
    end
    cleaned.gsub(/&#x([0-9a-fA-F]+);/) do |match|
      codepoint = $1.to_i(16)
      codepoint <= 0x10FFFF ? match : ""
    end
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
    result.gsub!(CLEANUP_MIXED_WHITESPACE_REGEX, "\n\n")

    # Fix 1: Multiple consecutive spaces → single space (but preserve indentation at line start)
    result.gsub!(CLEANUP_MULTIPLE_SPACES_REGEX, '\1 ')

    # Fix 2: Empty parentheses → remove (both ASCII and Japanese)
    result.gsub!(CLEANUP_EMPTY_PARENS_REGEX, "")

    # Fix 3: Leftover pipe characters (table/infobox remnants)
    result.gsub!(CLEANUP_MULTIPLE_PIPES_REGEX, "")
    result.gsub!(CLEANUP_TRAILING_PIPE_REGEX, "")
    result.gsub!(CLEANUP_PIPE_LINE_REGEX, "")
    # Lines with multiple pipe-separated key=value pairs (infobox remnants)
    result.gsub!(CLEANUP_KEY_VALUE_LINE_REGEX, "")
    # Template name remnants (data-driven from template_aliases.json)
    result.gsub!(CLEANUP_REMNANTS_REGEX, "")
    # Imagemap/gallery remnants: lines like "Image:file.jpg|thumb|...|caption" without [[ brackets
    result.gsub!(CLEANUP_FILE_LINE_REGEX, "")
    # Incomplete File/Image links (opened but not closed on same logical unit)
    result.gsub!(CLEANUP_FILE_INCOMPLETE_REGEX, "")
    # Orphaned closing brackets from split File links (e.g., "caption]] rest of text")
    result.gsub!(CLEANUP_ORPHANED_CLOSE_REGEX, '\1')
    # Orphaned opening brackets and standalone ]] lines (combined for single pass)
    result.gsub!(CLEANUP_ORPHANED_BRACKETS_REGEX, "")
    # ]] preceded by pipe without matching [[ (orphaned from broken links)
    result.gsub!(CLEANUP_PIPE_CLOSE_REGEX) { "#{$1}#{$2}" }

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
    result.gsub!(CLEANUP_MULTI_BLANK_REGEX, "\n\n")

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
    res.gsub!(IMAGEMAP_COORD_REGEX, "")
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

  # =========================================================================
  # Make constants Ractor-shareable for parallel processing
  # =========================================================================
  module_function

  def self.make_constants_ractor_shareable!
    return unless defined?(Ractor) && Ractor.respond_to?(:make_shareable)

    constants(false).each do |const_name|
      const = const_get(const_name)
      next if Ractor.shareable?(const)

      begin
        Ractor.make_shareable(const)
      rescue Ractor::IsolationError, FrozenError, TypeError
        # Some constants can't be made shareable, skip them
      end
    end
  end

  make_constants_ractor_shareable!
end
