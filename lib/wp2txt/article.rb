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
  
  # an article contains elements, each of which is [TYPE, string]
  class Article
    
    include Wp2txt
    attr_accessor :elements, :title
    
    # class varialbes to save resource for generating regexps
    # those with a trailing number 1 represent opening tag/markup
    # those with a trailing number 2 represent closing tag/markup
    # those without a trailing number contain both opening/closing tags/markups
    
    @@in_template_regex = Regexp.new('^\s*\{\{[^\}]+\}\}\s*$')
    @@in_link_regex = Regexp.new('^\s*\[.*\]\s*$')
        
    @@in_inputbox_regex  = Regexp.new('<inputbox>.*?<\/inputbox>')
    @@in_inputbox_regex1  = Regexp.new('<inputbox>')
    @@in_inputbox_regex2  = Regexp.new('<\/inputbox>')
    
    @@in_source_regex  = Regexp.new('<source.*?>.*?<\/source>')
    @@in_source_regex1  = Regexp.new('<source.*?>')
    @@in_source_regex2  = Regexp.new('<\/source>')
    
    @@in_math_regex  = Regexp.new('<math.*?>.*?<\/math>')
    @@in_math_regex1  = Regexp.new('<math.*?>')
    @@in_math_regex2  = Regexp.new('<\/math>')
    
    @@in_heading_regex  = Regexp.new('^=+.*?=+$')
    
    @@in_html_table_regex = Regexp.new('<table.*?><\/table>')
    @@in_html_table_regex1 = Regexp.new('<table\b')
    @@in_html_table_regex2 = Regexp.new('<\/\s*table>')
    
    @@in_summary_regex = Regexp.new('^\s*\{\{.*?\}\}\s*$')
    @@in_summary_regex1 = Regexp.new('^\s*\{\{[^\{]*$')
    @@in_summary_regex2 = Regexp.new('\}\}\s*$')
    
    @@in_table_regex1 = Regexp.new('^\W*\{\|')
    @@in_table_regex2 = Regexp.new('^\|\}.*?$')
    
    @@in_blockquote_regex = Regexp.new('^\:')
    @@in_unordered_regex  = Regexp.new('^\*')
    @@in_ordered_regex    = Regexp.new('^\#')
    @@in_pre_regex = Regexp.new('^ ')
    @@in_definition_regex  = Regexp.new('^[\;\:]')    
    
    @@blank_line_regex = Regexp.new('^\s*$')

    def initialize(text, title = "")
      @title = title.strip
      parse text
    end
    
    def create_element(tp, text)
      [tp, text]
    end
  
    def parse(source)
      @elements = []
      mode = nil
      open_stack  = []
      close_stack = []
      source.gsub!(/\<\!\-\-.*?\-\-\>/m){"\n"}
      source.each_line do |line|

        case mode
        when :mw_summary
          open_stack  += line.scan(/\{\{/)
          close_stack += line.scan(/\}\}/)          
          if @@in_summary_regex2 =~ line
            if open_stack.size == close_stack.size
              mode = nil
              open_stack.clear
              close_stack.clear
            end
          end
          @elements.last.last << line
          next
        when :mw_table
          if @@in_table_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next          
        when :mw_inputbox
          if @@in_inputbox_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        when :mw_source
          if @@in_source_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        when :mw_math
          if @@in_math_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        when :mw_htable
          if @@in_html_table_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        end

        case line
        when @@blank_line_regex
          @elements << create_element(:mw_blank, "\n")      
        when @@in_template_regex
          @elements << create_element(:mw_template, line)
        when @@in_heading_regex
          @elements << create_element(:mw_heading, "\n" + line + "\n")
        when @@in_inputbox_regex
          @elements << create_element(:mw_inputbox, line)
        when @@in_inputbox_regex1
          mode = :mw_inputbox 
          @elements << create_element(:mw_inputbox, line)
        when @@in_source_regex
        @elements << create_element(:mw_source, line)
        when @@in_source_regex1
          mode = :mw_source
          @elements << create_element(:mw_source, line)
        when @@in_math_regex
          @elements << create_element(:mw_math, line)
        when @@in_math_regex1
          mode = :mw_math
          @elements << create_element(:mw_math, line)
        when @@in_html_table_regex
          @elements << create_element(:mw_htable, line)
        when @@in_html_table_regex1
          mode = :mw_htable
          @elements << create_element(:mw_htable, line)
        when @@in_summary_regex
          @elements << create_element(:mw_summary, line)
        when @@in_summary_regex1
          mode = :mw_summary
          open_stack  += line.scan(/\{\{/)
          close_stack += line.scan(/\}\}/)
          @elements << create_element(:mw_summary, line)
        when @@in_table_regex1
          mode = :mw_table
          @elements << create_element(:mw_table, line)
        when @@in_unordered_regex
          # line = format_wiki(line) unless $DEBUG_MODE
          @elements << create_element(:mw_unordered, line)
        when @@in_ordered_regex
          # line = format_wiki(line) unless $DEBUG_MODE
          @elements << create_element(:mw_ordered, line)
        when @@in_pre_regex
          @elements << create_element(:mw_pre, line)
        when @@in_definition_regex
          # line = format_wiki(line) unless $DEBUG_MODE
          @elements << create_element(:mw_definition, line)
        when @@in_link_regex
          @elements << create_element(:mw_link, line)
        else #when @@in_paragraph_regex
          # line = format_wiki(line) unless $DEBUG_MODE
          @elements << create_element(:mw_paragraph, line)
        end
      end
      @elements
    end
  end
end
