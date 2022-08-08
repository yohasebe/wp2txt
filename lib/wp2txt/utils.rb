#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'strscan'
require 'find'
require 'htmlentities'

###################################################
# global variables to save resource for generating regexps
# those with a trailing number 1 represent opening tag/markup
# those with a trailing number 2 represent closing tag/markup
# those without a trailing number contain both opening/closing tags/markups

$html_decoder = HTMLEntities.new

$entities = ['&nbsp;', '&lt;', '&gt;', '&amp;', '&quot;'].zip([' ', '<', '>', '&', '"'])
$html_hash  = Hash[*$entities.flatten]
$html_regex = Regexp.new("(" + $html_hash.keys.join("|") + ")")
$ml_template_onset_regex = Regexp.new('^\{\{[^\}]*$')
$ml_template_end_regex   = Regexp.new('\}\}\s*$')
$ml_link_onset_regex = Regexp.new('^\[\[[^\]]*$')
$ml_linkend_regex   = Regexp.new('\]\]\s*$')
$isolated_template_regex = Regexp.new('^\s*\{\{.+\}\}\s*$')
$isolated_tag_regex = Regexp.new('^\s*\<[^\<\>]+\>.+\<[^\<\>]+\>\s*$')
$in_link_regex = Regexp.new('^\s*\[.*\]\s*$')
$in_inputbox_regex  = Regexp.new('<inputbox>.*?<\/inputbox>')
$in_inputbox_regex1  = Regexp.new('<inputbox>')
$in_inputbox_regex2  = Regexp.new('<\/inputbox>')
$in_source_regex  = Regexp.new('<source.*?>.*?<\/source>')
$in_source_regex1  = Regexp.new('<source.*?>')
$in_source_regex2  = Regexp.new('<\/source>')
$in_math_regex  = Regexp.new('<math.*?>.*?<\/math>')
$in_math_regex1  = Regexp.new('<math.*?>')
$in_math_regex2  = Regexp.new('<\/math>')
$in_heading_regex  = Regexp.new('^=+.*?=+$')
$in_html_table_regex = Regexp.new('<table.*?><\/table>')
$in_html_table_regex1 = Regexp.new('<table\b')
$in_html_table_regex2 = Regexp.new('<\/\s*table>')
$in_table_regex1 = Regexp.new('^\s*\{\|')
$in_table_regex2 = Regexp.new('^\|\}.*?$')
$in_unordered_regex  = Regexp.new('^\*')
$in_ordered_regex    = Regexp.new('^\#')
$in_pre_regex = Regexp.new('^ ')
$in_definition_regex  = Regexp.new('^[\;\:]')    
$blank_line_regex = Regexp.new('^\s*$')
$redirect_regex = Regexp.new('#(?:REDIRECT|転送)\s+\[\[(.+)\]\]', Regexp::IGNORECASE)
$remove_tag_regex = Regexp.new("\<[^\<\>]*\>")
$remove_directives_regex = Regexp.new("\_\_[^\_]*\_\_")
$remove_emphasis_regex = Regexp.new('(' + Regexp.escape("''") + '+)(.+?)\1')
$chrref_to_utf_regex = Regexp.new('&#(x?)([0-9a-fA-F]+);')
$mndash_regex = Regexp.new('\{(mdash|ndash|–)\}')
$remove_hr_regex = Regexp.new('^\s*\-+\s*$')
$make_reference_regex_a = Regexp.new('<br ?\/>')
$make_reference_regex_b = Regexp.new('<ref[^>]*\/>')
$make_reference_regex_c = Regexp.new('<ref[^>]*>')
$make_reference_regex_d = Regexp.new('<\/ref>')
$format_ref_regex = Regexp.new('\[ref\](.*?)\[\/ref\]', Regexp::MULTILINE)
$heading_onset_regex = Regexp.new('^(\=+)\s+')
$heading_coda_regex = Regexp.new('\s+(\=+)$')
$list_marks_regex = Regexp.new('\A[\*\#\;\:\ ]+')
$pre_marks_regex = Regexp.new('\A\^\ ')
$def_marks_regex = Regexp.new('\A[\;\:\ ]+')
$onset_bar_regex = Regexp.new('\A[^\|]+\z')

$category_patterns = ["Category", "Categoria"].join("|")
$category_regex = Regexp.new('[\{\[\|\b](?:' + $category_patterns + ')\:(.*?)[\}\]\|\b]', Regexp::IGNORECASE)

$escape_nowiki_regex = Regexp.new('<nowiki>(.*?)<\/nowiki>', Regexp::MULTILINE)
$unescape_nowiki_regex = Regexp.new('<nowiki\-(\d+?)>')

$remove_isolated_regex = Regexp.new('^\s*\{\{(.*?)\}\}\s*$')
$remove_inline_regex = Regexp.new('\{\{(.*?)\}\}')
$type_code_regex = Regexp.new('\A(?:lang*|\AIPA|IEP|SEP|indent|audio|small|dmoz|pron|unicode|note label|nowrap|ArabDIN|trans|Nihongo|Polytonic)', Regexp::IGNORECASE)

$single_square_bracket_regex = Regexp.new("(#{Regexp.escape('[')}|#{Regexp.escape(']')})", Regexp::MULTILINE)
$double_square_bracket_regex = Regexp.new("(#{Regexp.escape('[[')}|#{Regexp.escape(']]')})", Regexp::MULTILINE)
$single_curly_bracket_regex = Regexp.new("(#{Regexp.escape('{')}|#{Regexp.escape('}')})", Regexp::MULTILINE)
$double_curly_bracket_regex = Regexp.new("(#{Regexp.escape('{{')}|#{Regexp.escape('}}')})", Regexp::MULTILINE)
$curly_square_bracket_regex = Regexp.new("(#{Regexp.escape('{|')}|#{Regexp.escape('|}')})", Regexp::MULTILINE)

$complex_regex_01 = Regexp.new('\<\<([^<>]++)\>\>\s?')
$complex_regex_02 = Regexp.new('\[\[File\:((?:[^\[\]]++|\[\[\g<1>\]\])++)\]\]', Regexp::MULTILINE | Regexp::IGNORECASE)
$complex_regex_03 = Regexp.new('^\[\[((?:[^\[\]]++|\[\[\g<1>\]\])++)^\]\]', Regexp::MULTILINE)
$complex_regex_04 = Regexp.new('\{\{(?:infobox|efn|sfn|unreliable source|refn|reflist|col(?:umns)?\-list|div col|no col|bar box|formatnum\:|col\||see also\||r\||#)((?:[^{}]++|\{\{\g<1>\}\})++)\}\}', Regexp::MULTILINE | Regexp::IGNORECASE)
$complex_regex_05 = Regexp.new('\{\{[^{}]+?\n\|((?:[^{}]++|\{\{\g<1>\}\})++)\}\}', Regexp::MULTILINE | Regexp::IGNORECASE)

$cleanup_regex_01 = Regexp.new('\[ref\]\s*\[\/ref\]', Regexp::MULTILINE)
$cleanup_regex_02 = Regexp.new('^File:.+$')
$cleanup_regex_03 = Regexp.new('^\|.*$')
$cleanup_regex_04 = Regexp.new('\{\{.*$')
$cleanup_regex_05 = Regexp.new('^.*\}\}')
$cleanup_regex_06 = Regexp.new('\{\|.*$')
$cleanup_regex_07 = Regexp.new('^.*\|\}')
$cleanup_regex_08 = Regexp.new('\n\n\n+', Regexp::MULTILINE)

###################################################

module Wp2txt

  def convert_characters!(text, has_retried = false)
    begin 
      text << "" 
      chrref_to_utf!(text)
      special_chr!(text)
      
    rescue # detect invalid byte sequence in UTF-8
      if has_retried
        puts "invalid byte sequence detected"
        puts "******************************"
        File.open("error_log.txt", "w") do |f|
          f.write text
        end
        exit
      else
        text.encode!("UTF-16")
        text.encode!("UTF-8")
        convert_characters!(text, true)
      end
    end
  end
  
  def format_wiki!(text, has_retried = false)
    remove_complex!(text)

    escape_nowiki!(text)
    process_interwiki_links!(text)
    process_external_links!(text)
    unescape_nowiki!(text)      
    remove_directive!(text)
    remove_emphasis!(text)
    mndash!(text)
    remove_hr!(text)
    remove_tag!(text)
    correct_inline_template!(text) unless $leave_inline_template
    remove_templates!(text) unless $leave_inline_template
    remove_table!(text) unless $leave_table
  end
  
  def cleanup!(text)
    text.gsub!($cleanup_regex_01){""}
    text.gsub!($cleanup_regex_02){""}
    text.gsub!($cleanup_regex_03){""}
    text.gsub!($cleanup_regex_04){""}
    text.gsub!($cleanup_regex_05){""}
    text.gsub!($cleanup_regex_06){""}
    text.gsub!($cleanup_regex_07){""}
    text.gsub!($cleanup_regex_08){"\n\n"}
    text.strip!
    text << "\n\n"
  end

  #################### parser for nested structure ####################
   
  def process_nested_structure(scanner, left, right, &block)
    test = false
    buffer = ""
    begin
      if left == "[" && right == "]"
        regex = $single_square_bracket_regex
      elsif left == "[[" && right == "]]"
        regex = $double_square_bracket_regex
      elsif left == "{" && right == "}"
        regex = $single_curly_bracket_regex
      elsif left == "{{" && right == "}}"
        regex = $double_curly_bracket_regex
      elsif left == "{|" && right == "|}"
        regex = $curly_square_bracket_regex
      else
        regex = Regexp.new("(#{Regexp.escape(left)}|#{Regexp.escape(right)})")
      end
      while str = scanner.scan_until(regex)
        case scanner[1]
        when left
          buffer << str
          has_left = true
        when right
          if has_left
            buffer = buffer[0...-(left.size)]
            contents = block.call(str[0...-(left.size)])
            buffer << contents
            break
          else
            buffer << str
          end
        end
      end
      buffer << scanner.rest

      if buffer == scanner.string
        return buffer
      else
        scanner.string = buffer
        return process_nested_structure(scanner, left, right, &block) || ""
      end
    rescue => e
      return scanner.string
    end
  end  

  #################### methods used from format_wiki ####################
  def escape_nowiki!(str)
    if @nowikis
      @nowikis.clear
    else
      @nowikis = {}
    end
    str.gsub!($escape_nowiki_regex) do
      nowiki = $1
      nowiki_id = nowiki.object_id
      @nowikis[nowiki_id] = nowiki
      "<nowiki-#{nowiki_id}>"
    end
  end

  def unescape_nowiki!(str)
    str.gsub!($unescape_nowiki_regex) do
      obj_id = $1.to_i
      @nowikis[obj_id]
    end
  end
      
  def process_interwiki_links!(str)
    scanner = StringScanner.new(str)
    result = process_nested_structure(scanner, "[[", "]]") do |contents|
      parts = contents.split("|")      
      case parts.size
      when 1
        parts.first || ""
      else
        parts.shift
        parts.join("|")
      end
    end
    str.replace(result)
  end

  def process_external_links!(str)
    scanner = StringScanner.new(str)
    result = process_nested_structure(scanner, "[", "]") do |contents|
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
    str.replace(result)
  end

  #################### methods used from format_article ####################

  def remove_templates!(str)
    scanner = StringScanner.new(str)
    result = process_nested_structure(scanner, "{{", "}}") do |contents|
      ""
    end
    scanner = StringScanner.new(result)
    result = process_nested_structure(scanner, "{", "}") do |contents|
      ""
    end
    str.replace(result)
  end
  
  def remove_table!(str)
    scanner = StringScanner.new(str)
    result = process_nested_structure(scanner, "{|", "|}") do |contents|
      ""
    end
    str.replace(result)
  end
  
  def special_chr!(str)
    str.replace $html_decoder.decode(str)
  end

  def remove_inbetween!(str, tagset = ['<', '>'])
    tagsets = Regexp.quote(tagset.uniq.join(""))
    regex = /#{Regexp.escape(tagset[0])}[^#{tagsets}]*#{Regexp.escape(tagset[1])}/
    str.gsub!(regex, "")
  end

  def remove_tag!(str)
    str.gsub!($remove_tag_regex, "")
  end

  def remove_directive!(str)
    str.gsub!($remove_directives_regex, "")
  end

  def remove_emphasis!(str)
    str.gsub!($remove_emphasis_regex) do
      $2
    end
  end

  def chrref_to_utf!(num_str)
    begin
      num_str.gsub!($chrref_to_utf_regex) do
        if $1 == 'x'
          ch = $2.to_i(16)
        else
          ch = $2.to_i
        end
        hi = ch>>8
        lo = ch&0xff
        u = "\377\376" << lo.chr << hi.chr
        u.encode("UTF-8", "UTF-16")
      end
    rescue StandardError
      return nil
    end
    return true
  end
  
  def mndash!(str)
    str.gsub!($mndash_regex, "–")
  end

  def remove_hr!(str)
    str.gsub!($remove_hr_regex, "")
  end

  def remove_ref!(str)
    str.gsub!($format_ref_regex){""}
  end

  def remove_html!(str)
    str.gsub!(/<[^<>]+\/>/){""}
    ["div", "gallery", "timeline", "noinclude"].each do |tag|
      scanner = StringScanner.new(str)
      result = process_nested_structure(scanner, "<#{tag}", "#{tag}>") do |contents|
        ""
      end
      str.replace(result)
    end
  end

  def remove_complex!(str)
    str.gsub!($complex_regex_01){"《#{$1}》"}
    str.gsub!($complex_regex_02){""}
    str.gsub!($complex_regex_03){""}
    str.gsub!($complex_regex_04){""}
    str.gsub!($complex_regex_05){""}
  end
  
  def make_reference!(str)
    str.gsub!($make_reference_regex_a){"\n"}
    str.gsub!($make_reference_regex_b){""}
    str.gsub!($make_reference_regex_c){"[ref]"}
    str.gsub!($make_reference_regex_d){"[/ref]"}
  end

  def correct_inline_template!(str)
    scanner = StringScanner.new(str)
    result = process_nested_structure(scanner, "{{", "}}") do |contents|
      parts = contents.split("|")
      if /\A(?:lang|fontsize)\z/i =~ parts[0]
        parts.shift
      elsif /\Alang\-/i =~ parts[0]
        parts.shift
      elsif /\Alang=/i =~ parts[1]
        parts.shift
      end

      if parts.size == 1
        out = parts[0]
      else
        begin
          keyval = parts[1].split("=")
          if keyval.size > 1
            out = keyval[1]
          else
            out = parts[1] || ""
          end
        rescue
          out = parts[1] || ""
        end
      end

      out.strip
    end
    str.replace result
  end

#################### file related utilities ####################

  # collect filenames recursively
  def collect_files(str, regex = nil)
    regex ||= //
    text_array = Array.new
    Find.find(str) do |f|
      text_array << f if regex =~ f
    end
    text_array.sort
  end

  # modify a file using block/yield mechanism
  def file_mod(file_path, backup = false, &block)
    File.open(file_path, "r") do |fr|
      str = fr.read
      newstr = yield(str)
      str = newstr unless newstr == nil
      File.open("temp", "w") do |tf|
        tf.write(str)
      end
    end

    File.rename(file_path, file_path + ".bak")
    File.rename("temp", file_path)
    File.unlink(file_path + ".bak") unless backup
  end  

  # modify files under a directry (recursive)
  def batch_file_mod(dir_path, &block)
    if FileTest.directory?(dir_path)
      collect_files(dir_path).each do |file|
        yield file if FileTest.file?(file)
      end
    else   
      yield dir_path if FileTest.file?(dir_path)
    end
  end

  # take care of difference of separators among environments
  def correct_separator(input)
    if input.is_a?(String)
      ret_str = String.new
      if RUBY_PLATFORM.index("win32")
        ret_str = input.gsub("/", "\\")
      else
        ret_str = input.gsub("\\", "/")
      end
      return ret_str
    elsif input.is_a?(Array)
      ret_array = Array.new
      input.each do |item|
        ret_array << correct_separator(item)
      end
      return ret_array
    end
  end

  def rename(files, ext = "txt")    
    # num of digits necessary to name the last file generated
    maxwidth = 0  

    files.each do |f|
      width = f.slice(/\-(\d+)\z/, 1).to_s.length.to_i
      maxwidth = width if maxwidth < width
    end

    files.each do |f|
      newname= f.sub(/\-(\d+)\z/) do
        "-" + sprintf("%0#{maxwidth}d", $1.to_i)
      end
      File.rename(f, newname + ".#{ext}")
    end
    return true
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
    str = sprintf("%02d:%02d:%02d", h, m, s)
    return str
  end

  def decimal_format(i)
    str = i.to_s.reverse
    return str.scan(/.?.?./).join(',').reverse
  end
end
