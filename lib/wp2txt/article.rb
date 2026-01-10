# frozen_string_literal: true

require 'strscan'
require_relative 'utils'

module Wp2txt
  # possible element type, which could be later chosen to print or not to print
  # :mw_heading
  # :mw_htable
  # :mw_quote
  # :mw_unordered
  # :mw_ordered
  # :mw_definition
  # :mw_pre
  # :mw_paragraph
  # :mw_comment
  # :mw_math
  # :mw_source
  # :mw_inputbox
  # :mw_template
  # :mw_link
  # :mw_summary
  # :mw_blank
  # :mw_redirect

  # an article contains elements, each of which is [TYPE, string]
  class Article
    include Wp2txt
    attr_accessor :elements, :title, :categories

    def initialize(text, title = "", strip_tmarker = false)
      @title = title.strip
      @strip_tmarker = strip_tmarker
      text = convert_characters(text)
      text = text.gsub(/\|\n\n+/m) { "|\n" }
      text = remove_html(text)
      text = make_reference(text)
      text = remove_ref(text)
      parse text
    end

    def create_element(tpx, text)
      [tpx, text]
    end

    # Create a heading element with level information
    # @param text [String] The heading text (with or without = markers)
    # @param level [Integer] The heading level (2 for ==, 3 for ===, etc.)
    # @return [Array] [:mw_heading, text, level]
    def create_heading_element(text, level)
      [:mw_heading, text, level]
    end

    # Extract heading level from line with = markers
    # @param line [String] The heading line (e.g., "== Heading ==")
    # @return [Integer] The heading level (count of = signs)
    def extract_heading_level(line)
      match = line.match(/^(=+)/)
      match ? match[1].length : 2
    end

    # Extract clean heading text without = markers
    # @param line [String] The heading line
    # @return [String] The heading text without = markers
    def extract_heading_text(line)
      line.gsub(/^=+\s*/, "").gsub(/\s*=+$/, "").strip
    end

    # Check if a line has unbalanced [[ ]] brackets
    # Returns true if there are more [[ than ]] (indicating multi-line link)
    def has_unbalanced_link_brackets?(line)
      open_count = line.scan(/\[\[/).size
      close_count = line.scan(/\]\]/).size
      open_count > close_count
    end

    # Process a line in multi-line template mode, tracking brace depth
    # Updates @brace_depth and returns remaining content after }} if template closed, nil otherwise
    def process_ml_template_line(line)
      pos = 0
      close_pos = nil

      while pos < line.length
        open_idx = line.index("{{", pos)
        close_idx = line.index("}}", pos)

        if open_idx && (!close_idx || open_idx < close_idx)
          @brace_depth += 1
          pos = open_idx + 2
        elsif close_idx
          @brace_depth -= 1
          pos = close_idx + 2
          if @brace_depth == 0
            close_pos = close_idx + 2
            break
          end
        else
          break
        end
      end

      if close_pos
        # Template closed at close_pos
        template_part = line[0...close_pos]
        remaining = line[close_pos..]
        @elements.last.last << template_part
        remaining
      else
        # Template continues
        @elements.last.last << line
        nil
      end
    end

    def parse(source)
      @elements = []
      @categories = []
      mode = nil
      @brace_depth = 0
      source.each_line do |line|
        # Collect categories without deduplicating on each line (O(n²) → O(n))
        matched = line.scan(CATEGORY_REGEX)
        @categories.concat(matched) if matched && !matched.empty?

        case mode
        when :mw_ml_template
          # Track brace depth to find where template actually ends
          remaining = process_ml_template_line(line)
          if remaining
            # Template closed, remaining content needs to be processed
            mode = nil
            # Process remaining content if any
            unless remaining.strip.empty?
              @elements << create_element(:mw_paragraph, "\n" + remaining)
            end
          end
          next
        when :mw_ml_link
          scanner = StringScanner.new(line)
          str = process_nested_structure(scanner, "[[", "]]") { "" }
          mode = nil if ML_LINK_END_REGEX =~ str
          @elements.last.last << line
          next
        when :mw_table
          mode = nil if IN_TABLE_REGEX2 =~ line
          @elements.last.last << line
          next
        when :mw_inputbox
          mode = nil if IN_INPUTBOX_REGEX2 =~ line
          @elements.last.last << line
          next
        when :mw_source
          mode = nil if IN_SOURCE_REGEX2 =~ line
          @elements.last.last << line
          next
        when :mw_math
          mode = nil if IN_MATH_REGEX2 =~ line
          @elements.last.last << line
          next
        when :mw_htable
          mode = nil if IN_HTML_TABLE_REGEX2 =~ line
          @elements.last.last << line
          next
        end

        case line
        when ISOLATED_TEMPLATE_REGEX
          @elements << create_element(:mw_isolated_template, line)
        when ISOLATED_TAG_REGEX
          @elements << create_element(:mw_isolated_tag, line)
        when BLANK_LINE_REGEX
          @elements << create_element(:mw_blank, "\n")
        when REDIRECT_REGEX
          @elements << create_element(:mw_redirect, line)
        when IN_HEADING_REGEX
          level = extract_heading_level(line)
          # Keep original format for backward compatibility, but also store level
          formatted_line = line.sub(HEADING_ONSET_REGEX) { $1 }.sub(HEADING_CODA_REGEX) { $1 }
          @elements << create_heading_element("\n" + formatted_line + "\n", level)
        when IN_INPUTBOX_REGEX
          @elements << create_element(:mw_inputbox, line)
        when ML_TEMPLATE_ONSET_REGEX
          @elements << create_element(:mw_ml_template, line)
          mode = :mw_ml_template
          # Count initial braces: count {{ minus }} in this line
          @brace_depth = line.scan(/\{\{/).size - line.scan(/\}\}/).size
        when ML_LINK_ONSET_REGEX
          # Only treat as multi-line link if brackets are actually unbalanced
          if has_unbalanced_link_brackets?(line)
            @elements << create_element(:mw_ml_link, line)
            mode = :mw_ml_link
          else
            # Brackets are balanced, treat as paragraph
            @elements << create_element(:mw_paragraph, "\n" + line)
          end
        when IN_INPUTBOX_REGEX1
          mode = :mw_inputbox
          @elements << create_element(:mw_inputbox, line)
        when IN_SOURCE_REGEX
          @elements << create_element(:mw_source, line)
        when IN_SOURCE_REGEX1
          mode = :mw_source
          @elements << create_element(:mw_source, line)
        when IN_MATH_REGEX
          @elements << create_element(:mw_math, line)
        when IN_MATH_REGEX1
          mode = :mw_math
          @elements << create_element(:mw_math, line)
        when IN_HTML_TABLE_REGEX
          @elements << create_element(:mw_htable, line)
        when IN_HTML_TABLE_REGEX1
          mode = :mw_htable
          @elements << create_element(:mw_htable, line)
        when IN_TABLE_REGEX1
          mode = :mw_table
          @elements << create_element(:mw_table, line)
        when IN_UNORDERED_REGEX
          line = line.sub(LIST_MARKS_REGEX, "") if @strip_tmarker
          @elements << create_element(:mw_unordered, line)
        when IN_ORDERED_REGEX
          line = line.sub(LIST_MARKS_REGEX, "") if @strip_tmarker
          @elements << create_element(:mw_ordered, line)
        when IN_PRE_REGEX
          line = line.sub(PRE_MARKS_REGEX, "") if @strip_tmarker
          @elements << create_element(:mw_pre, line)
        when IN_DEFINITION_REGEX
          line = line.sub(DEF_MARKS_REGEX, "") if @strip_tmarker
          @elements << create_element(:mw_definition, line)
        when IN_LINK_REGEX
          @elements << create_element(:mw_link, line)
        else
          @elements << create_element(:mw_paragraph, "\n" + line)
        end
      end
      # Deduplicate categories once at the end (O(n) instead of O(n²))
      @categories.uniq!
      @elements
    end
  end
end
