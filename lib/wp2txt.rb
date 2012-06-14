#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$: << File.join(File.dirname(__FILE__))

require "rubygems"
require "bundler/setup"
require "nokogiri"

require "wp2txt/article"
require "wp2txt/utils"
require "wp2txt/mw_api"
require "wp2txt/progressbar"

begin
  require "bzip2-ruby"
  NO_BZ2 = false  
rescue LoadError
  # in case bzip2-ruby gem is not available
  NO_BZ2 = true
end

module Wp2txt
  class Runner

    include Wp2txt

    # attr_accessor :pause_flag, :stop_flag, :outfiles, :convert_off

    def initialize(parent, input_file, output_dir = ".", tfile_size = 10, convert_off = false, strip_tmarker = false)
      @parent = parent
      @fp = nil
      
      @input_file = input_file
      @output_dir = output_dir
      @tfile_size = tfile_size
      @convert_off = convert_off
      @strip_tmarker = strip_tmarker
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
    
    # control the display of command line progressbar (or gui which is not available for now)
    def notify_parent(last = false)
      @last_time ||= Time.now.to_f
      @elapsed_sum ||= 0
      time_now = Time.now.to_f
      elapsed_from_last = (time_now - @last_time).to_i

      if elapsed_from_last > 0.3 || last

        @last_time = time_now        
        @elapsed_sum += elapsed_from_last
        gvalue = (@size_read.to_f / @infile_size.to_f * 100 * 100).to_i
        elt_str = sec_to_str(@elapsed_sum)
        if last
          eta_str = "00:00:00"
        else
          lines_persec = @size_read / @elapsed_sum if @elapsed_sum > 0
          eta_sec = (@infile_size - @size_read) / lines_persec
          eta_str = sec_to_str(eta_sec)
        end
        @parent.prg_update(gvalue, elt_str, eta_str)
      end
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
          @parent.msg("Preparing ... This may take several minutes or more ", 0)         
          @infile_size = file_size(file)
          @parent.msg("... Done.", 1)
          file.close
          file = Bzip2::Reader.new File.open(@input_file, "r:UTF-8")
        else
          if RUBY_PLATFORM.index("win32")
            file = IO.popen("bunzip2.exe -c #{@input_file}")
          else
            file = IO.popen("bzip2 -c -d #{@input_file}") 
          end
          @infile_size = file_size(file)
          file.close  # try to reopen since rewind method is unavailable
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
      @parent.before
      @parent.data_set(@input_file, 100 * 100)
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

    def get_page
      inside_page = false
      page = ""
      while line = get_newline
        notify_parent        
        @size_read ||=0; @size_read += line.bytesize
        
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
        return page.force_encoding("utf-8")
      end
    end

    # call this method to do the job
    def extract_text(&block)
      prepare            
      # output the original xml only split to files of the specified size
      if @convert_off
        extract
        # convert xml to plain text
      else
        if block
          extract_and_convert(&block)
        else
          extract_and_convert
        end
      end
    end
    
    def extract_and_convert(&block)
      in_text = false
      in_message = false
      result_text = ""
      title = nil
      end_flag = false
      terminal_round = false
      output_text = ""

      while page = get_page
        xmlns = '<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.5/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.mediawiki.org/xml/export-0.5/ http://www.mediawiki.org/xml/export-0.5.xsd" version="0.5" xml:lang="en">' + "\n"
        xml = xmlns + page + "</mediawiki>"
        input = Nokogiri::XML(xml, nil, 'UTF-8')
        page = input.xpath("//xmlns:text").first                
        pp_title = page.parent.parent.at_css "title"
        title = pp_title.content

        next if /\:/ =~ title        
        text = page.content
        # remove all comment texts
        # and insert as many number of new line chars included in 
        # each comment instead
        text.gsub!(/\<\!\-\-(.*?)\-\-\>/m) do |content|
          num_of_newlines = content.count("\n")
          if num_of_newlines = 0
            ""
          else
            "\n" * num_of_newlines
          end
        end
        
        @count ||= 0;@count += 1;        

        article = Article.new(text, title, @strip_tmarker)
        output_text += block.call(article)
        @total_size = output_text.bytesize

        # flagged when data exceeds the size of output file
        end_flag = true if @total_size > (@tfile_size * 1024 * 1024)

        #close the present file, then open a new one
        if end_flag
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
      notify_parent(true)
      @parent.after
      @fp.close    
      rename(@outfiles)    
      @parent.msg("Processing finished", 1)
    end

    def extract
      output_text = ""
      end_flag = false
      while text = get_newline
        @count ||= 0;@count += 1;
        @size_read ||=0;@size_read += text.bytesize
        @total_size += text.bytesize
        output_text << text
        end_flag = true if @total_size > (@tfile_size * 1024 * 1024)
        notify_parent
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
      notify_parent(true)
      @parent.after
      @fp.close    
      rename(@outfiles)    
      @parent.msg("Processing finished", 1)
    end 
  end
end