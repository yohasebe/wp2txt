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

    def parse(source)
      @elements = []
      @categories = []
      mode = nil
      source.each_line do |line|
        matched = line.scan(CATEGORY_REGEX)
        if matched && !matched.empty?
          @categories += matched
          @categories.uniq!
        end

        case mode
        when :mw_ml_template
          scanner = StringScanner.new(line)
          str = process_nested_structure(scanner, "{{", "}}") { "" }
          mode = nil if ML_TEMPLATE_END_REGEX =~ str
          @elements.last.last << line
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
          line = line.sub(HEADING_ONSET_REGEX) { $1 }.sub(HEADING_CODA_REGEX) { $1 }
          @elements << create_element(:mw_heading, "\n" + line + "\n")
        when IN_INPUTBOX_REGEX
          @elements << create_element(:mw_inputbox, line)
        when ML_TEMPLATE_ONSET_REGEX
          @elements << create_element(:mw_ml_template, line)
          mode = :mw_ml_template
        when ML_LINK_ONSET_REGEX
          @elements << create_element(:mw_ml_link, line)
          mode = :mw_ml_link
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
      @elements
    end
  end
end
