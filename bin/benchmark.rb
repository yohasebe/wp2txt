#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$: << File.join(File.dirname(__FILE__))
$: << File.join(File.dirname(__FILE__), '..', 'lib')

require 'wp2txt'
require 'wp2txt/utils'
include Wp2txt
require 'benchmark'

data_dir = File.join(File.dirname(__FILE__), '..', "data")

parent = Wp2txt::CmdProgbar.new
input_file = File.join(data_dir, "testdata.bz2")
output_dir = data_dir
tfile_size = 10
convert = true
strip_tmarker = true



Benchmark.bm do |x|
  x.report do
    wpconv = Wp2txt::Runner.new(parent, input_file, output_dir, tfile_size, convert, strip_tmarker)
    wpconv.extract_text do |article|
      title = format_wiki article.title
      title = "[[#{title}]]\n"

        contents = "\nCATEGORIES: "
        contents += article.categories.join(", ")
        contents += "\n\n"

      article.elements.each do |e|
        case e.first
        when :mw_heading
          line = format_wiki(e.last)
        when :mw_paragraph
          line = format_wiki(e.last)
        when :mw_table, :mw_htable
          line = format_wiki(e.last)
        when :mw_pre
          line = e.last
        when :mw_quote
          line = format_wiki(e.last)
        when :mw_unordered, :mw_ordered, :mw_definition
          line = format_wiki(e.last)
        when :mw_redirect
          line = format_wiki(e.last)
          line += "\n\n"
        else
          next
        end
        contents += line
        contents = remove_templates(contents)
      end
    
      ##### cleanup #####
      if /\A\s*\z/m =~ contents
        result = ""
      else
        result = title + "\n" + contents
      end
      result = result.gsub(/\[ref\]\s*\[\/ref\]/m){""}
      result = result.gsub(/\n\n\n+/m){"\n\n"} + "\n"  
    end
  end
end

