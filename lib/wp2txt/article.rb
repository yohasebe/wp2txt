#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$: << File.join(File.dirname(__FILE__))


require 'strscan'
require 'utils'

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
      convert_characters!(text)    
      make_reference!(text)
      remove_ref!(text)
      
      parse text
    end
    
    def create_element(tp, text)
      [tp, text]
    end
  
    def parse(source)
      @elements = []
      @categories  = []
      mode = nil
      open_stack  = []
      close_stack = []
      source.each_line do |line|
        matched = line.scan($category_regex)
        if matched && !matched.empty?
          @categories += matched
          @categories.uniq!
        end

        case mode
        when :mw_ml_template
          scanner = StringScanner.new(line)
          str= process_nested_structure(scanner, "{{", "}}") {""}
          if $ml_template_end_regex =~ str
            mode = nil
          end
          @elements.last.last << line
          next
        when :mw_ml_link
          scanner = StringScanner.new(line)
          str= process_nested_structure(scanner, "[[", "]]") {""}
          if $ml_link_end_regex =~ str
            mode = nil
          end
          @elements.last.last << line
          next
        when :mw_table
          if $in_table_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next          
        when :mw_inputbox
          if $in_inputbox_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        when :mw_source
          if $in_source_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        when :mw_math
          if $in_math_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        when :mw_htable
          if $in_html_table_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        end

        case line
        when $isolated_template_regex
          @elements << create_element(:mw_isolated_template, line)
        when $isolated_tag_regex
          @elements << create_element(:mw_isolated_tag, line)
        when $blank_line_regex
          @elements << create_element(:mw_blank, "\n")      
        when $redirect_regex
          @elements << create_element(:mw_redirect, line)
        # when $in_template_regex
        #   @elements << create_element(:mw_template, line)
        when $in_heading_regex
          line = line.sub($heading_onset_regex){$1}.sub($heading_coda_regex){$1}          
          @elements << create_element(:mw_heading, "\n" + line + "\n")
        when $in_inputbox_regex
          @elements << create_element(:mw_inputbox, line)
        when $ml_template_onset_regex 
          @elements << create_element(:mw_ml_template, line)
          mode = :mw_ml_template
        when $ml_link_onset_regex 
          @elements << create_element(:mw_ml_link, line)
          mode = :mw_ml_link
        when $in_inputbox_regex1
          mode = :mw_inputbox
          @elements << create_element(:mw_inputbox, line)
        when $in_source_regex
        @elements << create_element(:mw_source, line)
        when $in_source_regex1
          mode = :mw_source
          @elements << create_element(:mw_source, line)
        when $in_math_regex
          @elements << create_element(:mw_math, line)
        when $in_math_regex1
          mode = :mw_math
          @elements << create_element(:mw_math, line)
        when $in_html_table_regex
          @elements << create_element(:mw_htable, line)
        when $in_html_table_regex1
          mode = :mw_htable
          @elements << create_element(:mw_htable, line)
        when $in_table_regex1
          mode = :mw_table
          @elements << create_element(:mw_table, line)
        when $in_unordered_regex
          line = line.sub($list_marks_regex, "") if @strip_tmarker          
          @elements << create_element(:mw_unordered, line)
        when $in_ordered_regex
          line = line.sub($list_marks_regex, "") if @strip_tmarker          
          @elements << create_element(:mw_ordered, line)
        when $in_pre_regex
          line = line.sub($pre_marks_regex, "") if @strip_tmarker          
          @elements << create_element(:mw_pre, line)
        when $in_definition_regex
          line = line.sub($def_marks_regex, "") if @strip_tmarker
          @elements << create_element(:mw_definition, line)
        when $in_link_regex
          @elements << create_element(:mw_link, line)
        else 
          @elements << create_element(:mw_paragraph, "\n" + line)
        end
      end
      @elements
    end
  end
end
