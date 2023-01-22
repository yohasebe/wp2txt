# frozen_string_literal: true

require "strscan"
require "find"
require_relative "regex"

module Wp2txt
  def convert_characters(text, has_retried = false)
    text << ""
    text = chrref_to_utf(text)
    text = special_chr(text)
    text = text.encode("UTF-8", "UTF-8", invalid: :replace, replace: "")
  rescue StandardError # detect invalid byte sequence in UTF-8
    if has_retried
      puts "invalid byte sequence detected"
      puts "******************************"
      File.open("error_log.txt", "w") do |f|
        f.write text
      end
      exit
    else
      text = text.encode("UTF-16", "UTF-16", invalid: :replace, replace: "")
      text = text.encode("UTF-16", "UTF-16", invalid: :replace, replace: "")
      convert_characters(text, true)
    end
  end

  def format_wiki(text, config = {})
    text = remove_complex(text)
    text = escape_nowiki(text)
    text = process_interwiki_links(text)
    text = process_external_links(text)
    text = unescape_nowiki(text)
    text = remove_directive(text)
    text = remove_emphasis(text)
    text = mndash(text)
    text = remove_hr(text)
    text = remove_tag(text)
    text = correct_inline_template(text) unless config[:inline]
    text = remove_templates(text) unless config[:inline]
    text = remove_table(text) unless config[:table]
    text
  end

  def cleanup(text)
    text = text.gsub(CLEANUP_REGEX_01) { "" }
    text = text.gsub(CLEANUP_REGEX_02) { "" }
    text = text.gsub(CLEANUP_REGEX_03) { "" }
    text = text.gsub(CLEANUP_REGEX_04) { "" }
    text = text.gsub(CLEANUP_REGEX_05) { "" }
    text = text.gsub(CLEANUP_REGEX_06) { "" }
    text = text.gsub(CLEANUP_REGEX_07) { "" }
    text = text.gsub(CLEANUP_REGEX_08) { "\n\n" }
    text = text.strip
    text << "\n\n"
  end

  #################### parser for nested structure ####################

  def process_nested_structure(scanner, left, right, &block)
    buffer = +""
    begin
      regex = if left == "[" && right == "]"
                SINGLE_SQUARE_BRACKET_REGEX
              elsif left == "[[" && right == "]]"
                DOUBLE_SQUARE_BRACKET_REGEX
              elsif left == "{" && right == "}"
                SINGLE_CURLY_BRACKET_REGEX
              elsif left == "{{" && right == "}}"
                DOUBLE_CURLY_BRACKET_REGEX
              elsif left == "{|" && right == "|}"
                CURLY_SQUARE_BRACKET_REGEX
              else
                Regexp.new("(#{Regexp.escape(left)}|#{Regexp.escape(right)})")
              end
      while (str = scanner.scan_until(regex))
        case scanner[1]
        when left
          buffer << str
          has_left = true
        when right
          if has_left
            buffer = buffer[0...-left.size]
            contents = block.call(str[0...-left.size])
            buffer << contents
            break
          else
            buffer << str
          end
        end
      end
      buffer << scanner.rest

      return buffer if buffer == scanner.string

      scanner.string = buffer
      process_nested_structure(scanner, left, right, &block) || ""
    rescue StandardError
      scanner.string
    end
  end

  #################### methods used from format_wiki ####################
  def escape_nowiki(str)
    if @nowikis
      @nowikis.clear
    else
      @nowikis = {}
    end
    str.gsub(ESCAPE_NOWIKI_REGEX) do
      nowiki = $1
      nowiki_id = nowiki.object_id
      @nowikis[nowiki_id] = nowiki
      "<nowiki-#{nowiki_id}>"
    end
  end

  def unescape_nowiki(str)
    str.gsub(UNESCAPE_NOWIKI_REGEX) do
      obj_id = $1.to_i
      @nowikis[obj_id]
    end
  end

  def process_interwiki_links(str)
    scanner = StringScanner.new(str)
    process_nested_structure(scanner, "[[", "]]") do |contents|
      parts = contents.split("|")
      case parts.size
      when 1
        parts.first || ""
      else
        parts.shift
        parts.join("|")
      end
    end
  end

  def process_external_links(str)
    scanner = StringScanner.new(str)
    process_nested_structure(scanner, "[", "]") do |contents|
      if /\A\s.+\s\z/ =~ contents
        " (#{contents.strip}) "
      else
        parts = contents.split(" ", 2)
        case parts.size
        when 1
          parts.first || ""
        else
          parts.last || ""
        end
      end
    end
  end

  #################### methods used from format_article ####################

  def remove_templates(str)
    scanner1 = StringScanner.new(str)
    result = process_nested_structure(scanner1, "{{", "}}") do
      ""
    end
    scanner2 = StringScanner.new(result)
    process_nested_structure(scanner2, "{", "}") do
      ""
    end
  end

  def remove_table(str)
    scanner = StringScanner.new(str)
    process_nested_structure(scanner, "{|", "|}") do
      ""
    end
  end

  def special_chr(str)
    HTML_DECODER.decode(str)
  end

  def remove_inbetween(str, tagset = ["<", ">"])
    tagsets = Regexp.quote(tagset.uniq.join(""))
    regex = /#{Regexp.escape(tagset[0])}[^#{tagsets}]*#{Regexp.escape(tagset[1])}/
    str.gsub(regex, "")
  end

  def remove_tag(str)
    str.gsub(REMOVE_TAG_REGEX, "")
  end

  def remove_directive(str)
    str.gsub(REMOVE_DIRECTIVES_REGEX, "")
  end

  def remove_emphasis(str)
    str.gsub(REMOVE_EMPHASIS_REGEX) do
      $2
    end
  end

  def chrref_to_utf(num_str)
    num_str.gsub(CHRREF_TO_UTF_REGEX) do
      ch = if $1 == "x"
             $2.to_i(16)
           else
             $2.to_i
           end
      hi = ch >> 8
      lo = ch & 0xff
      u = +"\377\376" << lo.chr << hi.chr
      u.encode("UTF-8", "UTF-16")
    end
  rescue StandardError
    num_str
  end

  def mndash(str)
    str.gsub(MNDASH_REGEX, "–")
  end

  def remove_hr(str)
    str.gsub(REMOVE_HR_REGEX, "")
  end

  def remove_ref(str)
    str.gsub(FORMAT_REF_REGEX) { "" }
  end

  def remove_html(str)
    res = +str.dup
    res.gsub!(%r{<[^<>]+/>}) { "" }
    ["div", "gallery", "timeline", "noinclude"].each do |tag|
      scanner = StringScanner.new(res)
      result = process_nested_structure(scanner, "<#{tag}", "#{tag}>") do
        ""
      end
      res.replace(result)
    end
    res
  end

  def remove_complex(str)
    str = str.gsub(COMPLEX_REGEX_01) { "《#{$1}》" }
    str = str.gsub(COMPLEX_REGEX_02) { "" }
    str = str.gsub(COMPLEX_REGEX_03) { "" }
    str = str.gsub(COMPLEX_REGEX_04) { "" }
    str.gsub(COMPLEX_REGEX_05) { "" }
  end

  def make_reference(str)
    str = str.gsub(MAKE_REFERENCE_REGEX_A) { "\n" }
    str = str.gsub(MAKE_REFERENCE_REGEX_B) { "" }
    str = str.gsub(MAKE_REFERENCE_REGEX_C) { "[ref]" }
    str.gsub(MAKE_REFERENCE_REGEX_D) { "[/ref]" }
  end

  def correct_inline_template(str)
    scanner = StringScanner.new(str)
    process_nested_structure(scanner, "{{", "}}") do |contents|
      parts = contents.split("|")
      if /\A(?:lang|fontsize)\z/i =~ parts[0]
        parts.shift
      elsif /\Alang-/i =~ parts[0]
        parts.shift
      elsif /\Alang=/i =~ parts[1]
        parts.shift
      end

      if parts.size == 1
        out = parts[0]
      else
        begin
          keyval = parts[1].split("=")
          out = if keyval.size > 1
                  keyval[1]
                else
                  parts[1] || ""
                end
        rescue StandardError
          out = parts[1] || ""
        end
      end
      out.strip
    end
  end

  #################### file related utilities ####################

  # collect filenames recursively
  def collect_files(str, regex = nil)
    regex ||= //
    text_array = []
    Find.find(str) do |f|
      text_array << f if regex =~ f
    end
    text_array.sort
  end

  # modify a file using block/yield mechanism
  def file_mod(file_path, backup = false)
    File.open(file_path, "r") do |fr|
      str = fr.read
      newstr = yield(str)
      str = newstr if nil? newstr
      File.open("temp", "w") do |tf|
        tf.write(str)
      end
    end

    File.rename(file_path, file_path + ".bak")
    File.rename("temp", file_path)
    File.unlink(file_path + ".bak") unless backup
  end

  # modify files under a directry (recursive)
  def batch_file_mod(dir_path)
    if FileTest.directory?(dir_path)
      collect_files(dir_path).each do |file|
        yield file if FileTest.file?(file)
      end
    elsif FileTest.file?(dir_path)
      yield dir_path
    end
  end

  # take care of difference of separators among environments
  def correct_separator(input)
    case input
    when String
      if RUBY_PLATFORM.index("win32")
        input.gsub("/", "\\")
      else
        input.gsub("\\", "/")
      end
    when Array
      ret_array = []
      input.each do |item|
        ret_array << correct_separator(item)
      end
      ret_array
    end
  end

  def rename(files, ext = "txt")
    # num of digits necessary to name the last file generated
    maxwidth = 0

    files.each do |f|
      width = f.slice(/-(\d+)\z/, 1).to_s.length.to_i
      maxwidth = width if maxwidth < width
      newname = f.sub(/-(\d+)\z/) do
        "-" + format("%0#{maxwidth}d", $1.to_i)
      end
      File.rename(f, newname + ".#{ext}")
    end
    true
  end

  # convert int of seconds to string in the format 00:00:00
  def sec_to_str(int)
    unless int
      str = "--:--:--"
      return str
    end
    h = int / 3600
    m = (int - h * 3600) / 60
    s = int % 60
    format("%02d:%02d:%02d", h, m, s)
  end
end
