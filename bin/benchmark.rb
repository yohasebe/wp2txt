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
input_file = File.join(data_dir, "testdata_ja.bz2")
output_dir = data_dir
tfile_size = 10
num_threads = 1
convert = true
strip_tmarker = true

Benchmark.bm do |x|
  x.report do
    wpconv = Wp2txt::Runner.new(parent, input_file, output_dir, tfile_size, num_threads, convert, strip_tmarker)
    wpconv.extract_text do |article|
      format_wiki!(article.title)
      title = "[[#{article.title}]]\n"
      convert_characters!(title)

      contents = "\nCATEGORIES: "
      contents += article.categories.join(", ")
      contents += "\n\n"

      article.elements.each do |e|
        case e.first
        when :mw_heading
          format_wiki!(e.last)
          line = e.last
        when :mw_paragraph
          format_wiki!(e.last)
          line = e.last
        when :mw_table, :mw_htable
          format_wiki!(e.last)
          line = e.last
        when :mw_pre
          line = e.last
        when :mw_quote
          format_wiki!(e.last)
          line = e.last
        when :mw_unordered, :mw_ordered, :mw_definition
          format_wiki!(e.last)
          line = e.last
        when :mw_redirect
          format_wiki!(e.last)
          line = e.last
          line += "\n\n"
        else
          next
        end
        contents << line
      end
      format_wiki!(contents)
      convert_characters!(contents)

      ##### cleanup #####
      if /\A[\s　]*\z/m =~ contents
        result = ""
      else
        result = title + "\n" + contents
      end
      result = result.gsub(/\[ref\]\s*\[\/ref\]/m){""}
      result = result.gsub(/\n\n\n+/m){"\n\n"} + "\n"  
    end
  end
end

