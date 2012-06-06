#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'strscan'
require 'wputils'

module WikipediaParser

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
  
  class Article
    attr_accessor :elements
    include WikipediaUtils
    # class varialbes to save resource for generating regexps
    @@in_comment_regex = Regexp.new('^\s*<\!\-\-.*?\-\->\s*$')
    @@in_comment_regex1 = Regexp.new('^\s*<\!\-\-')
    @@in_comment_regex2 = Regexp.new('\-\->\s*$')
    @@in_source_regex  = Regexp.new('<source.*?>.*?<\/source>', Regexp::MULTILINE)
    @@in_source_regex1  = Regexp.new('<source.*?>', Regexp::MULTILINE)
    @@in_source_regex2  = Regexp.new('<\/source>', Regexp::MULTILINE)
    @@in_math_regex  = Regexp.new('<math.*?>.*?<\/math>', Regexp::MULTILINE)
    @@in_math_regex1  = Regexp.new('<math.*?>', Regexp::MULTILINE)
    @@in_math_regex2  = Regexp.new('<\/math>', Regexp::MULTILINE)    
    @@in_heading_regex  = Regexp.new('^=+.*?=+$')
    @@in_html_table_regex1 = Regexp.new('<table\b', Regexp::MULTILINE)
    @@in_html_table_regex2 = Regexp.new('<\/\s*table>', Regexp::MULTILINE)
    @@in_summary_regex1 = Regexp.new('^\W*\{\{')
    @@in_summary_regex2 = Regexp.new('^\}\}.*?$')
    @@in_table_regex1 = Regexp.new('^\W*\{\|')
    @@in_table_regex2 = Regexp.new('^\|\}.*?$')
    @@in_blockquote_regex1 = Regexp.new('^\:')
    @@in_blockquote_regex2 = Regexp.new('^\:')
    @@in_unordered_regex1  = Regexp.new('^\*')
    @@in_unordered_regex2  = Regexp.new('^\*')
    @@in_ordered_regex1    = Regexp.new('^\#')
    @@in_ordered_regex2    = Regexp.new('^\#')
    @@in_definition_regex1  = Regexp.new('^\;')
    @@in_definition_regex2  = Regexp.new('^\:')
    @@in_pre_regex1 = Regexp.new('^ ')
    @@in_pre_regex2 = Regexp.new('^ ')
    @@in_paragraph_regex = Regexp.new('^[^\<\=\:\*\#\s(:?\{\|)]')
      
    def initialize(str, title = "", lang = "EN", w_separated = true)
      @title = title.strip
      @lang = lang
      @w_separated = w_separated
      parse str
    end

    def title
      @title || ""
    end
    
    def to_s
      text = "[[" + title + "]]\n"
      @elements.each do |element|
        text += element + "\n"
      end
      return text
    end
    
    def create_element(tp, text)
      [tp, text]
    end
  
    def parse(str)
      @elements = []
      element = nil
      mode = nil
      
      str.each_line do |line|
        line.chomp!
        
        skip = false
        if /^\s*$/ =~ line
          skip = true
        end
        if /^\s*\[\[.*\]\]\s*$/ =~ line
          skip = true
        end
        if /^\s*\{\{.*\}\}\s*$/ =~ line
          skip = true
        end
         
        if skip and mode != :in_comment
          @elements << element if element
          element = nil
          mode = nil
          next
        end
        
        case mode
        when :heading
          ;
        when :in_definition
          if @@in_definition_regex1 =~ line
            element.last << line.sub(/^[\:\;\*\# ]+/, "- ").chomp + "\n"
            next
          elsif @@in_definition_regex2 =~ line
            element.last << line.sub(/^[\:\;\*\# ]+/, "- ").chomp + "\n"
            next
          else
            mode = nil
          end
        when :in_comment
          if @@in_comment_regex2 =~ line
            mode = nil
          end
          next
        when :in_source
          if @@in_source_regex2 =~ line + "\n"
            mode = nil
          end
          next
        when :in_math
          if @@in_math_regex2 =~ line + "\n"
            mode = nil
          end
          next
        when :in_html_table
          if @@in_html_table_regex2 =~ line + "\n"
            mode = nil
          end
          element.last << line.chomp
          next
        when :in_summary
          if @@in_summary_regex2 =~ line + "\n"
            mode = nil
          end
          element.last << line.chomp
          next
        when :in_table
          if @@in_table_regex2 =~ line + "\n"
            mode = nil
          end
          element.last << line.chomp
          next
        when :in_blockquote
          if @@in_blockquote_regex2 =~ line
            element.last << line.sub(/^[\:\;\*\# ]+/, "> ").chomp + "\n"
            next
          end
        when :in_unordered
          if @@in_unordered_regex2 =~ line
            element.last << line.sub(/^[\:\;\*\# ]+/, "* ").chomp + "\n"
            next
          end
        when :in_ordered
          if @@in_ordered_regex2 =~ line
            element.last << line.sub(/^[\:\;\*\# ]+/, "# ").chomp + "\n"
            next
          end
        when :in_pre
          if @@in_pre_regex2 =~ line
            element.last << line.chomp + "\n"
            next
          end
        end
    
        case line
        when @@in_comment_regex
        when @@in_comment_regex1
          @elements << element if element
          mode = :in_comment
          element = nil
        when @@in_source_regex
          @elements << element if element
          element = nil 
          mode = nil
        when @@in_source_regex1
          @elements << element if element
          mode = :in_source
          element = nil 
        when @@in_math_regex
          @elements << element if element
          element = nil 
          mode = nil
        when @@in_math_regex1
          @elements << element if element
          mode = :in_math
          element = nil 
        when @@in_heading_regex
          @elements << element if element
          mode = :heading
          element = create_element(HEADING, line)          
        when @@in_html_table_regex1
          @elements << element if element
          mode = :in_html_table
          element = create_element(HTABLE, line)
        when @@in_summary_regex1
          @elements << element if element
          mode = :in_summary
          element = create_element(SUMMARY, line.sub(/^[\:\;\*\# ]+/, "").chomp + "\n")
        when @@in_table_regex1
          @elements << element if element
          mode = :in_table        
          element = create_element(TABLE, line.sub(/^[\:\;\*\# ]+/, "").chomp + "\n")
        when @@in_blockquote_regex1
          @elements << element if element
          mode = :in_blockquote
          element = create_element(QUOTE, line.sub(/^[\:\;\*\# ]+/, "> ").chomp + "\n")
        when @@in_unordered_regex1
          @elements << element if element
          mode = :in_unordered
          element = create_element(UNORDERED, line.sub(/^[\:\;\*\# ]+/, "* ").chomp + "\n")          
        when @@in_ordered_regex1
          @elements << element if element
          mode = :in_ordered
          element = create_element(ORDERED, line.sub(/^[\:\;\*\# ]+/, "# ").chomp + "\n")
        when @@in_definition_regex1
          @elements << element if element
          mode = :in_definition
          element = create_element(DEFINITION, line.sub(/^[\:\;\*\# ]+/, "- ").chomp + "\n")
        when @@in_pre_regex1
          @elements << element if element
          mode = :in_pre
          element = create_element(PRE, line)
        else
          if mode == :in_paragraph
            # begin
            if /\s\$/ =~ element.last
              element.last << line.chomp
            else
              element.last << (" " + line.chomp)
            end
            next
            # rescue
            #   p line
            # end
          end
          @elements << element if element
          mode = :in_paragraph
          element = create_element(PARAGRAPH, line.chomp)
        end
        # @elements.pop if !element || element.last.chomp == ""
      end
      @elements << element if element && element.last.chomp != ""
    end
  end
end
