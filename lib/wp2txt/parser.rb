#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$: << File.join(File.dirname(__FILE__))

require 'strscan'
require 'utils'

module Wp2txt::Parser

  # element type, which could be later chosen to print or not to print
  HEADING    = 0
  HTABLE     = 1
  SUMMARY    = 2
  TABLE      = 3
  QUOTE      = 4
  UNORDERED  = 5
  ORDERED    = 6
  DEFINITION = 7
  PRE        = 8
  PARAGRAPH  = 9
  COMMENT    = 10
  MATH       = 11
  SOURCE     = 12
  INPUTBOX   = 13
  TEMPLATE   = 14
  LINK       = 15
  
  # an article contains elements, each of which is [TYPE, string]
  class Article
    
    include Wp2txt::TextUtils
    attr_accessor :elements, :title
    
    # class varialbes to save resource for generating regexps
    # those with a trailing number 1 represent opening tag/markup
    # those with a trailing number 2 represent closing tag/markup
    # those without a trailing number contain both opening/closing tags/markups
    
    @@in_template_regex = Regexp.new('^\s*\{\{[^\}]+\}\}\s*$')
    @@in_link_regex = Regexp.new('^\s*\[.*\]\s*$')
    
    @@in_comment_regex = Regexp.new('^\s*<\!\-\-.*?\-\->\s*$')
    @@in_comment_regex1 = Regexp.new('^\s*<\!\-\-')
    @@in_comment_regex2 = Regexp.new('\-\->\s*$')
    
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
    
    def format_elements(title_off, heading_off, paragraph_off, table_off, 
                        quote_off, list_off, paren_off, bracket_off)
      title = "[[" + special_chr(@title) + "]]\n\n"
      contents = ""
      line = ""
      @elements.each do |e|
        case e.first
        when HEADING
          next if heading_off
          line = e.last
          line += "+HEADING+" if $DEBUG_MODE
        when PARAGRAPH
          next if paragraph_off
          line = e.last
          line += "+PARAGRAPH+" if $DEBUG_MODE          
        when TABLE, HTABLE
          next if table_off
          line = e.last
          line += "+TABLE+" if $DEBUG_MODE
        when QUOTE, PRE
          next if quote_off
          line = e.last
          line += "+QUOTE+" if $DEBUG_MODE
        when UNORDERED, ORDERED, DEFINITION
          next if list_off
          line = e.last
          line += "+LIST+" if $DEBUG_MODE
        else
          if $DEBUG_MODE
            line = e.last + "+DEBUG+"
          end
          next
        end
        contents += (line + "\n") unless /\A\s*\z/ =~ line
      end

      if /\A\W*\z/m =~ contents
        result = ""
      else
        result = @title_off ? contents : title + contents
      end
      return result
    end

    def create_element(tp, text)
      [tp, text]
    end
  
    def parse(source)
      @elements = []
      mode = nil
      open_stack  = []
      close_stack = []
      source.each_line do |line|

        case mode
        when COMMENT
        when SUMMARY
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
        when TABLE
          if @@in_table_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
          
          if @@in_comment_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        when INPUTBOX
          if @@in_inputbox_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        when SOURCE
          if @@in_source_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        when MATH
          if @@in_math_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        when HTABLE
          if @@in_html_table_regex2 =~ line
            mode = nil
          end
          @elements.last.last << line
          next
        end

        case line
        when @@blank_line_regex
          ;      
        when @@in_template_regex
          @elements << create_element(TEMPLATE, line)      
        when @@in_heading_regex
          @elements << create_element(HEADING, line)      
        when @@in_comment_regex
          @elements << create_element(COMMENT, line)
        when @@in_comment_regex1
          mode = COMMENT
          @elements << create_element(COMMENT, line)        
        when @@in_inputbox_regex
          @elements << create_element(INPUTBOX, line)
        when @@in_inputbox_regex1
          @elements << create_element(INPUTBOX, line)      
        when @@in_source_regex
        @elements << create_element(SOURCE, line)          
        when @@in_source_regex1
          mode = SOURCE
          @elements << create_element(SOURCE, line)                
        when @@in_math_regex
          @elements << create_element(MATH, line)          
        when @@in_math_regex1
          mode = MATH
          @elements << create_element(MATH, line)          
        when @@in_html_table_regex
          @elements << create_element(HTABLE, line)          
        when @@in_html_table_regex1
          mode = HTABLE
          @elements << create_element(HTABLE, line)                
        when @@in_summary_regex
          @elements << create_element(SUMMARY, line)
        when @@in_summary_regex1
          mode = SUMMARY
          open_stack  += line.scan(/\{\{/)
          close_stack += line.scan(/\}\}/)
          @elements << create_element(SUMMARY, line)
        when @@in_table_regex1
          mode = TABLE    
          @elements << create_element(TABLE, line)          
        when @@in_unordered_regex
          line = format_wiki(line) unless $DEBUG_MODE
          @elements << create_element(UNORDERED, line) unless /^[\s\W]*$/ =~line
        when @@in_ordered_regex
          line = format_wiki(line) unless $DEBUG_MODE
          @elements << create_element(ORDERED, line) unless /^[\s\W]*$/ =~line
        when @@in_pre_regex
          @elements << create_element(PRE, line)
        when @@in_definition_regex
          line = format_wiki(line) unless $DEBUG_MODE
          @elements << create_element(DEFINITION, line) unless /^[\s\W]*$/ =~line
        when @@in_link_regex
          @elements << create_element(LINK, line)      
        else #when @@in_paragraph_regex
          line = format_wiki(line) unless $DEBUG_MODE
          @elements << create_element(PARAGRAPH, line) unless /^[\s\W]*$/ =~line
        end
      end
      @elements
    end
  end
end
