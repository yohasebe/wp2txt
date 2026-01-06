# frozen_string_literal: true

require "strscan"
require "find"
require_relative "regex"

module Wp2txt
  # Cache for dynamically generated regex patterns
  @regex_cache = {}
  class << self
    attr_accessor :regex_cache
  end

  def convert_characters(text, _has_retried = false)
    # Use scrub to safely handle invalid byte sequences
    text = text.to_s.scrub("")
    text = chrref_to_utf(text)
    text = special_chr(text)
    text.encode("UTF-8", "UTF-8", invalid: :replace, replace: "")
  rescue StandardError
    # If any encoding error persists, scrub again and return
    text.to_s.scrub("")
  end

  def format_wiki(text, config = {})
    # Work with a mutable copy to reduce intermediate string allocations
    result = +text.to_s
    result = remove_complex(result)
    result = escape_nowiki(result)
    result = process_interwiki_links(result)
    result = process_external_links(result)
    result = unescape_nowiki(result)
    # Use in-place modifications for simple regex replacements
    result.gsub!(REMOVE_DIRECTIVES_REGEX, "")
    result.gsub!(REMOVE_EMPHASIS_REGEX) { $2 }
    result.gsub!(MNDASH_REGEX, "–")
    result.gsub!(REMOVE_HR_REGEX, "")
    result.gsub!(REMOVE_TAG_REGEX, "")
    result = correct_inline_template(result) unless config[:inline]
    result = remove_templates(result) unless config[:inline]
    result = remove_table(result) unless config[:table]
    result
  end

  def cleanup(text)
    # Work with a mutable copy to reduce intermediate string allocations
    result = +text.to_s
    result.gsub!(CLEANUP_REGEX_01, "")
    result.gsub!(CLEANUP_REGEX_02, "")
    result.gsub!(CLEANUP_REGEX_03, "")
    result.gsub!(CLEANUP_REGEX_04, "")
    result.gsub!(CLEANUP_REGEX_05, "")
    result.gsub!(CLEANUP_REGEX_06, "")
    result.gsub!(CLEANUP_REGEX_07, "")
    result.gsub!(CLEANUP_REGEX_08, "\n\n")
    result.strip!
    result << "\n\n"
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
                # Use cached regex for custom bracket pairs
                cache_key = "#{left}|#{right}"
                Wp2txt.regex_cache[cache_key] ||= Regexp.new("(#{Regexp.escape(left)}|#{Regexp.escape(right)})")
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

  # File/Image namespace patterns (multilingual)
  FILE_NAMESPACES_REGEX = /\A\s*(?:File|Image|Media|Fichier|Datei|Bild|Archivo|Imagen|Immagine|Bestand|Afbeelding|Ficheiro|Imagem|Fil|Plik|Grafika|Soubor|Fișier|Imagine|Tiedosto|Kuva|Файл|Изображение|Зображення|Датотека|Слика|ファイル|画像|파일|文件|档案|檔案|ไฟล์|Tập tin|Hình|ملف|صورة|پرونده|تصویر|קובץ|תמונה)\s*:/i

  def process_interwiki_links(str)
    scanner = StringScanner.new(str)
    process_nested_structure(scanner, "[[", "]]") do |contents|
      parts = contents.split("|")
      first_part = parts.first || ""

      if FILE_NAMESPACES_REGEX.match?(first_part)
        # For File/Image links, extract caption (last non-parameter part)
        # Skip parts that look like parameters (contain =, or are size specs like 200px)
        if parts.size > 1
          caption = parts[1..].reverse.find do |p|
            !p.include?("=") && !p.match?(/^\d+px$/i) && !p.match?(/^(thumb|thumbnail|frame|frameless|border|right|left|center|none|upright|baseline|sub|super|top|text-top|middle|bottom|text-bottom)$/i)
          end
          caption || ""
        else
          ""
        end
      elsif parts.size == 1
        first_part
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
    # Use cached regex for common tagsets
    cache_key = "inbetween:#{tagset.join}"
    regex = Wp2txt.regex_cache[cache_key] ||= begin
      tagsets = Regexp.quote(tagset.uniq.join(""))
      Regexp.new("#{Regexp.escape(tagset[0])}[^#{tagsets}]*#{Regexp.escape(tagset[1])}")
    end
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
      codepoint = $1 == "x" ? $2.to_i(16) : $2.to_i
      # Handle all valid Unicode codepoints (U+0001 to U+10FFFF)
      if codepoint > 0 && codepoint <= 0x10FFFF
        [codepoint].pack("U")
      else
        ""
      end
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
    res = +str.to_s
    res.gsub!(SELF_CLOSING_TAG_REGEX, "")
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
    # Work with a mutable copy to reduce intermediate string allocations
    result = +str.to_s
    result.gsub!(COMPLEX_REGEX_01) { "《#{$1}》" }
    result.gsub!(COMPLEX_REGEX_02, "")
    result.gsub!(COMPLEX_REGEX_03, "")
    result.gsub!(COMPLEX_REGEX_04, "")
    result.gsub!(COMPLEX_REGEX_05, "")
    result
  end

  def make_reference(str)
    # Work with a mutable copy to reduce intermediate string allocations
    result = +str.to_s
    result.gsub!(MAKE_REFERENCE_REGEX_A, "\n")
    result.gsub!(MAKE_REFERENCE_REGEX_B, "")
    result.gsub!(MAKE_REFERENCE_REGEX_C, "[ref]")
    result.gsub!(MAKE_REFERENCE_REGEX_D, "[/ref]")
    result
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
      # Use tr instead of gsub for simple character replacement (faster)
      if RUBY_PLATFORM.index("win32")
        input.tr("/", "\\")
      else
        input.tr("\\", "/")
      end
    when Array
      input.map { |item| correct_separator(item) }
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
