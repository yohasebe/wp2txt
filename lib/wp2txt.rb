#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$: << File.join(File.dirname(__FILE__))

require "nokogiri"
require "wp2txt/article"
require "wp2txt/utils"

begin
  require "bzip2-ruby"
  NO_BZ2 = false  
rescue LoadError
  # in case bzip2-ruby gem is not available
  NO_BZ2 = true
end

module Wp2txt
  class Splitter
    include Wp2txt
    def initialize(input_file, output_dir = ".", tfile_size = 10)
      @fp = nil
      @input_file = input_file
      @output_dir = output_dir
      @tfile_size = tfile_size
      prepare            
    end
    
    def file_size(file) 
      origin = Time.now
      size = 0;  unit = 10485760; star = 0; before = Time.now.to_f
      error_count = 10
      while true do
        begin
          a = file.read(unit)
        rescue => e
          a = nil
        end
        break unless a    

        present = Time.now.to_f
        size += a.size
        if present - before > 0.3
          star = 0 if star > 10
          star += 1
          before = present
        end    
      end
      time_elapsed = Time.now - origin
      size
    end

    # check the size of input file (bz2 or plain xml) when uncompressed
    def prepare
      # if output_dir is not specified, output in the same directory
      # as the imput file
      if !@output_dir && @input_file
        @output_dir = File.dirname(@input_file)
      end

      # if input file is bz2 compressed, use bz2-ruby if available,
      # use command line bzip2 program otherwise.
      if /.bz2$/ =~ @input_file
        unless NO_BZ2
          file = Bzip2::Reader.new File.open(@input_file, "r:UTF-8")
        else
          if RUBY_PLATFORM.index("win32")
            file = IO.popen("bunzip2.exe -c #{@input_file}")
          else
            file = IO.popen("bzip2 -c -d #{@input_file}") 
          end
        end 
      else # meaning that it is a text file
        @infile_size = File.stat(@input_file).size
        file = open(@input_file)
      end

      #create basename of output file
      @outfile_base = File.basename(@input_file, ".*") + "-"            
      @total_size = 0
      @file_index = 1
      outfilename = File.join(@output_dir, @outfile_base + @file_index.to_s)
      @outfiles = []
      @outfiles << outfilename
      @fp = File.open(outfilename, "w")    
      @file_pointer = file
      return true
    end

    # read text data from bz2 compressed file by 1 megabyte
    def fill_buffer
      while true do
        begin
          new_lines = @file_pointer.read(10485760)
        rescue => e
          return nil
        end
        return nil unless new_lines

        # temp_buf is filled with text split by "\n"
        temp_buf = []
        ss = StringScanner.new(new_lines)
        while ss.scan(/.*?\n/m)             
          temp_buf << ss[0]
        end
        temp_buf << ss.rest unless ss.eos?

        new_first_line = temp_buf.shift
        if new_first_line[-1, 1] == "\n" # new_first_line.index("\n")
          @buffer.last <<  new_first_line
          @buffer << ""
        else
          @buffer.last << new_first_line
        end
        @buffer += temp_buf unless temp_buf.empty?
        if @buffer.last[-1, 1] == "\n" # @buffer.last.index("\n")
          @buffer << ""
        end
        break if @buffer.size > 1
      end
      return true
    end

    def get_newline
      @buffer ||= [""]   
      if @buffer.size == 1
        return nil unless fill_buffer
      end
      if @buffer.empty?
        return nil
      else 
        new_line = @buffer.shift
        return new_line
      end  
    end

    def split_file
      output_text = ""
      end_flag = false
      while text = get_newline
        @count ||= 0;@count += 1;
        @size_read ||=0
        @size_read += text.bytesize
        @total_size += text.bytesize
        output_text << text
        end_flag = true if @total_size > (@tfile_size * 1024 * 1024)
        # never close the file until the end of the page even if end_flag is on
        if end_flag && /<\/page/ =~ text 
          @fp.puts(output_text)
          output_text = ""
          @total_size = 0
          end_flag = false
          @fp.close
          @file_index += 1
          outfilename = File.join(@output_dir, @outfile_base + @file_index.to_s)
          @outfiles << outfilename
          @fp = File.open(outfilename, "w")
          next
        end
      end
      @fp.puts(output_text) if output_text != ""
      @fp.close    

      if File.size(outfilename) == 0
        File.delete(outfilename) 
        @outfiles.delete(outfilename)
      end

      rename(@outfiles, "xml")    
    end 
  end

  class Runner
    include Wp2txt

    def initialize(input_file, output_dir = ".", strip_tmarker = false, del_interfile = true)
      @fp = nil
      @input_file = input_file
      @output_dir = output_dir
      @strip_tmarker = strip_tmarker
      @del_interfile = del_interfile
      prepare
    end
    
    def prepare
      @infile_size = File.stat(@input_file).size
      file = open(@input_file)
      @file_pointer = file
      @outfile_base = File.basename(@input_file, ".*")
      @total_size = 0
      return true
    end

    def fill_buffer
      while true do
        begin
          new_lines = @file_pointer.read(10485760)
        rescue => e
          return nil
        end
        return nil unless new_lines

        # temp_buf is filled with text split by "\n"
        temp_buf = []
        ss = StringScanner.new(new_lines)
        while ss.scan(/.*?\n/m)             
          temp_buf << ss[0]
        end
        temp_buf << ss.rest unless ss.eos?

        new_first_line = temp_buf.shift
        if new_first_line[-1, 1] == "\n" # new_first_line.index("\n")
          @buffer.last <<  new_first_line
          @buffer << ""
        else
          @buffer.last << new_first_line
        end
        @buffer += temp_buf unless temp_buf.empty?
        if @buffer.last[-1, 1] == "\n" # @buffer.last.index("\n")
          @buffer << ""
        end
        break if @buffer.size > 1
      end
      return true
    end

    def get_newline
      @buffer ||= [""]   
      if @buffer.size == 1
        return nil unless fill_buffer
      end
      if @buffer.empty?
        return nil
      else 
        new_line = @buffer.shift
        return new_line
      end  
    end

    def get_page
      inside_page = false
      page = ""
      while line = get_newline
        if /<page>/ =~ line #
          page << line
          inside_page = true
          next
        elsif  /<\/page>/ =~ line #
          page << line
          inside_page = false
          break
        end
        page << line if inside_page
      end
      if page.empty?
        return false
      else
        return page.force_encoding("utf-8") rescue page
      end
    end

    def extract_text(&block)
      in_text = false
      in_message = false
      result_text = ""
      title = nil
      end_flag = false
      terminal_round = false
      output_text = ""
      pages = []
      data_empty = false

      while !data_empty 
        page = get_page
        if page
          pages << page
        else
          data_empty = true
        end
        if data_empty
          pages.each do |page|
            xmlns = '<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.5/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.mediawiki.org/xml/export-0.5/ http://www.mediawiki.org/xml/export-0.5.xsd" version="0.5" xml:lang="en">' + "\n"
            xml = xmlns + page + "</mediawiki>"

            input = Nokogiri::XML(xml, nil, 'UTF-8')
            page = input.xpath("//xmlns:text").first
            pp_title = page.parent.parent.at_css "title"
            title = pp_title.content
            unless  /\:/ =~ title
              text = page.content
              text.gsub!(/\<\!\-\-(.*?)\-\-\>/m) do |content|
                num_of_newlines = content.count("\n")
                if num_of_newlines == 0
                  ""
                else
                  "\n" * num_of_newlines
                end
              end
              article = Article.new(text, title, @strip_tmarker)
              page_text = block.call(article)
              output_text << page_text
            end
          end

          cleanup!(output_text)
          if output_text.size > 0
            outfilename = File.join(@output_dir, @outfile_base + ".txt")
            @fp = File.open(outfilename, "w")
            @fp.puts(output_text)
            @fp.close
          end
          File.delete(@input_file) if @del_interfile
          output_text = ""
        end
      end
    end
  end
end
