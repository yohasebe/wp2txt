# frozen_string_literal: true

require "nokogiri"
require_relative "wp2txt/article"
require_relative "wp2txt/utils"
require_relative "wp2txt/stream_processor"
require_relative "wp2txt/output_writer"

module Wp2txt
  class Splitter
    include Wp2txt

    attr_reader :size_read, :file_index

    def initialize(input_file, output_dir = ".", tfile_size = 10, bz2_gem = false, &progress_callback)
      @fp = nil
      @input_file = input_file
      @output_dir = output_dir
      @tfile_size = tfile_size
      require "bzip2-ruby" if bz2_gem
      @bz2_gem = bz2_gem
      @progress_callback = progress_callback
      @last_progress_time = Time.now
      prepare
    end

    def file_size(file)
      size = 0
      unit = 10_485_760
      star = 0
      before = Time.now.to_f

      loop do
        begin
          a = file.read(unit)
        rescue IOError, Errno::EIO, Errno::ENOENT
          a = nil
        end
        break unless a

        present = Time.now.to_f
        size += a.size

        next if present - before <= 0.3

        star = 0 if star > 10
        star += 1
        before = present
      end
      size
    end

    # check if a given command exists: return the path if it does, return false if not
    def command_exist?(command)
      basename = File.basename(command)
      print "Checking #{basename}: "
      begin
        # Use IO.popen instead of open("| ...") for Ruby 4.0 compatibility
        path = IO.popen(["which", command], err: File::NULL, &:read).strip
        if path.empty?
          path = IO.popen(["which", basename], err: File::NULL, &:read).strip
        end

        if path.empty?
          puts "#{basename} not found"
          false
        else
          puts "detected [#{path}]"
          path
        end
      rescue Errno::ENOENT, Errno::EPIPE, IOError
        puts "#{basename} not found"
        false
      end
    end

    # check the size of input file (bz2 or plain xml) when decompressed
    def prepare
      # if output_dir is not specified, output in the same directory
      # as the imput file
      @output_dir = File.dirname(@input_file) if !@output_dir && @input_file

      if /.bz2$/ =~ @input_file
        if @bz2_gem
          file = Bzip2::Reader.new File.open(@input_file, "r:UTF-8")
        elsif Gem.win_platform?
          file = IO.popen(["bunzip2.exe", "-c", @input_file])
        elsif (bzpath = command_exist?("lbzip2") || command_exist?("pbzip2") || command_exist?("bzip2"))
          file = IO.popen([bzpath, "-c", "-d", @input_file])
        end
      else # meaning that it is a text file
        @infile_size = File.stat(@input_file).size
        file = File.open(@input_file, "r:UTF-8")
      end

      # create basename of output file
      @outfile_base = File.basename(@input_file, ".*") + "-"
      @total_size = 0
      @file_index = 1
      outfilename = File.join(@output_dir, @outfile_base + @file_index.to_s)
      @outfiles = []
      @outfiles << outfilename
      @fp = File.open(outfilename, "w")
      @file_pointer = file
      true
    end

    # read text data from bz2 compressed file by 1 megabyte
    def fill_buffer
      loop do
        begin
          new_lines = @file_pointer.read(10_485_760)
        rescue IOError, Errno::EIO, Errno::ENOENT, Errno::EPIPE
          return nil
        end
        return nil unless new_lines

        # temp_buf is filled with text split by "\n"
        temp_buf = []
        ss = StringScanner.new(new_lines)
        temp_buf << ss[0] while ss.scan(/.*?\n/m)
        temp_buf << ss.rest unless ss.eos?

        new_first_line = temp_buf.shift
        @buffer.last << new_first_line
        # Use end_with? instead of [-1, 1] for clarity and performance
        @buffer << +"" if new_first_line.end_with?("\n")
        @buffer.concat(temp_buf) unless temp_buf.empty?
        @buffer << +"" if @buffer.last.end_with?("\n")
        break if @buffer.size > 1
      end
      true
    end

    def get_newline
      @buffer ||= [+""]
      if @buffer.size == 1 && !fill_buffer
        nil
      elsif @buffer.empty?
        nil
      else
        @buffer.shift
      end
    end

    def split_file
      output_text = +""
      end_flag = false
      while (text = get_newline)
        @count ||= 0
        @count += 1
        @size_read ||= 0
        @size_read += text.bytesize
        @total_size += text.bytesize
        output_text << text
        end_flag = true if @total_size > (@tfile_size * 1024 * 1024)

        # Report progress every 5 seconds
        report_progress

        # never close the file until the end of the page even if end_flag is on
        next unless end_flag && %r{</page} =~ text

        @fp.puts(output_text)
        output_text = +""
        @total_size = 0
        end_flag = false
        @fp.close
        @file_index += 1
        outfilename = File.join(@output_dir, @outfile_base + @file_index.to_s)
        @outfiles << outfilename
        @fp = File.open(outfilename, "w")
      end
      @fp.puts(output_text) unless output_text.empty?
      @fp.close

      if outfilename && File.size(outfilename).zero?
        File.delete(outfilename)
        @outfiles.delete(outfilename)
      end

      rename(@outfiles, "xml")
    end

    private

    def report_progress
      return unless @progress_callback

      now = Time.now
      return if now - @last_progress_time < 5 # Report every 5 seconds

      @last_progress_time = now
      @progress_callback.call(@size_read, @file_index)
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
      file = File.open(@input_file, "r:UTF-8")
      @file_pointer = file
      @outfile_base = File.basename(@input_file, ".*")
      @total_size = 0
      true
    end

    def fill_buffer
      loop do
        begin
          new_lines = @file_pointer.read(10_485_760)
        rescue IOError, Errno::EIO, Errno::ENOENT, Errno::EPIPE
          return nil
        end
        return nil unless new_lines

        # temp_buf is filled with text split by "\n"
        temp_buf = []
        ss = StringScanner.new(new_lines)
        temp_buf << ss[0] while ss.scan(/.*?\n/m)
        temp_buf << ss.rest unless ss.eos?

        new_first_line = temp_buf.shift
        @buffer.last << new_first_line
        # Use end_with? instead of [-1, 1] for clarity and performance
        @buffer << +"" if new_first_line.end_with?("\n")
        @buffer.concat(temp_buf) unless temp_buf.empty?
        @buffer << +"" if @buffer.last.end_with?("\n")
        break if @buffer.size > 1
      end
      true
    end

    def get_newline
      @buffer ||= [+""]
      if @buffer.size == 1 && !fill_buffer
        nil
      elsif @buffer.empty?
        nil
      else
        @buffer.shift
      end
    end

    def get_page
      inside_page = false
      page = +""
      while (line = get_newline)
        case line
        when /<page>/
          page << line
          inside_page = true
          next
        when %r{</page>}
          page << line
          inside_page = false
          break
        end
        page << line if inside_page
      end
      if page.empty?
        false
      else
        page.force_encoding("utf-8")
      end
    rescue ::Encoding::InvalidByteSequenceError, ::Encoding::UndefinedConversionError
      page
    end

    def extract_text(&block)
      title = nil
      output_text = +""
      pages = []
      data_empty = false

      until data_empty
        new_page = get_page
        if new_page
          pages << new_page
        else
          data_empty = true
        end
        next unless data_empty

        pages.each do |page|
          xmlns = '<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.5/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.mediawiki.org/xml/export-0.5/ http://www.mediawiki.org/xml/export-0.5.xsd" version="0.5" xml:lang="en">' + "\n"
          xml = xmlns + page + "</mediawiki>"

          input = Nokogiri::XML(xml, nil, 'UTF-8')
          page = input.xpath("//xmlns:text").first
          pp_title = page.parent.parent.at_css "title"
          title = pp_title.content
          next if /:/ =~ title

          text = page.content
          text.gsub!(/<!--(.*?)-->/m) do |content|
            num_of_newlines = content.count("\n")
            if num_of_newlines.zero?
              +""
            else
              "\n" * num_of_newlines
            end
          end
          article = Article.new(text, title, @strip_tmarker)
          page_text = block.call(article)
          output_text << page_text
        end

        output_text = cleanup(output_text)
        unless output_text.empty?
          outfilename = File.join(@output_dir, @outfile_base + ".txt")
          @fp = File.open(outfilename, "w")
          @fp.puts(output_text)
          @fp.close
        end
        @file_pointer.close
        File.delete(@input_file) if @del_interfile
        output_text = +""
      end
    end
  end
end
