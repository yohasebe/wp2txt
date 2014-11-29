#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'strscan'
require 'find'

###################################################
# global variables to save resource for generating regexps
# those with a trailing number 1 represent opening tag/markup
# those with a trailing number 2 represent closing tag/markup
# those without a trailing number contain both opening/closing tags/markups

$in_template_regex = Regexp.new('^\s*\{\{[^\}]+\}\}\s*$')
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
$remove_table_regex = Regexp.new('\{\|[^\{\|\}]*?\|\}', Regexp::MULTILINE)
$remove_clade_regex = Regexp.new('\{\{(?:C|c)lade[^\{\}]*\}\}', Regexp::MULTILINE)

$category_patterns = ["Category", "Categoria"].join("|")
$category_regex = Regexp.new('[\{\[\|\b](?:' + $category_patterns + ')\:(.*?)[\}\]\|\b]', Regexp::IGNORECASE)

$escape_nowiki_regex = Regexp.new('<nowiki>(.*?)<\/nowiki>', Regexp::MULTILINE)
$unescape_nowiki_regex = Regexp.new('<nowiki\-(\d+?)>')

$remove_inline_regex = Regexp.new('\{\{(.*?)\}\}')
$type_code_regex = Regexp.new('\A(?:lang*|\AIPA|IEP|SEP|indent|audio|small|dmoz|pron|unicode|note label|nowrap|ArabDIN|trans|Nihongo|Polytonic)', Regexp::IGNORECASE)

$single_square_bracket_regex = Regexp.new("(#{Regexp.escape('[')}|#{Regexp.escape(']')})", Regexp::MULTILINE)
$double_square_bracket_regex = Regexp.new("(#{Regexp.escape('[[')}|#{Regexp.escape(']]')})", Regexp::MULTILINE)
$single_curly_bracket_regex = Regexp.new("(#{Regexp.escape('{')}|#{Regexp.escape('}')})", Regexp::MULTILINE)
$double_curly_bracket_regex = Regexp.new("(#{Regexp.escape('{{')}|#{Regexp.escape('}}')})", Regexp::MULTILINE)

###################################################

module Wp2txt

  def format_wiki!(text, has_retried = false)
    begin 
      text << "" 
      
      chrref_to_utf!(text)
      escape_nowiki!(text)

      process_interwiki_links!(text)
      process_external_links!(text)

      unescape_nowiki!(text)
      
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
        format_wiki!(text, true)
      end
    end
  end

  #################### parser for nested structure ####################
   
  def process_nested_structure(scanner, left, right, recur_count, &block)
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
    else
      regex = Regexp.new('(#{Regexp.escape(left)}|#{Regexp.escape(right)})', Regexp::MULTILINE)
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

    recur_count = recur_count - 1
    if recur_count < 0 || buffer == scanner.string
      return buffer
    else
      scanner.string = buffer
      return process_nested_structure(scanner, left, right, recur_count, &block) || ""
    end
    rescue => e
      return scanner.string
    end
  end  

  #################### methods used from format_wiki ####################

  def remove_templates!(str)
    scanner = StringScanner.new(str)
    result = process_nested_structure(scanner, "{{", "}}", $limit_recur) do |contents|
      ""
    end
    str.replace(result)
  end
  
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
    result = process_nested_structure(scanner, "[[", "]]", $limit_recur) do |contents|
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
    result = process_nested_structure(scanner, "[", "]", $limit_recur) do |contents|
      parts = contents.split(" ", 2)
      case parts.size
      when 1
        parts.first || ""
      else
        parts.last || ""
      end
    end
    str.replace(result)
  end

  def special_chr!(str)
    unless $sp_hash 
      html = ['&nbsp;', '&lt;', '&gt;', '&amp;', '&quot;']\
      .zip([' ', '<', '>', '&', '"'])
      
      umraut_accent = ['&Agrave;', '&Aacute;', '&Acirc;', '&Atilde;', '&Auml;',
      '&Aring;', '&AElig;', '&Ccedil;', '&Egrave;', '&Eacute;', '&Ecirc;', 
      '&Euml;', '&Igrave;', '&Iacute;', '&Icirc;', '&Iuml;', '&Ntilde;', 
      '&Ograve;', '&Oacute;', '&Ocirc;', '&Otilde;', '&Ouml;', '&Oslash;', 
      '&Ugrave;', '&Uacute;', '&Ucirc;', '&Uuml;', '&szlig;', '&agrave;', 
      '&aacute;', '&acirc;', '&atilde;', '&auml;', '&aring;', '&aelig;', 
      '&ccedil;', '&egrave;', '&eacute;', '&ecirc;', '&euml;', '&igrave;', 
      '&iacute;', '&icirc;', '&iuml;', '&ntilde;', '&ograve;', '&oacute;',
      '&ocirc;', '&oelig;', '&otilde;', '&ouml;', '&oslash;', '&ugrave;', 
      '&uacute;', '&ucirc;', '&uuml;', '&yuml;']\
      .zip(['À', 'Á', 'Â', 'Ã', 'Ä', 'Å', 'Æ', 'Ç', 'È', 'É', 'Ê', 'Ë', 'Ì', 'Í', 
      'Î', 'Ï', 'Ñ', 'Ò', 'Ó', 'Ô', 'Õ', 'Ö', 'Ø', 'Ù', 'Ú', 'Û', 'Ü', 'ß', 'à', 
      'á', 'â', 'ã', 'ä', 'å', 'æ', 'ç', 'è', 'é', 'ê', 'ë', 'ì', 'í', 'î', 'ï', 
      'ñ', 'ò', 'ó', 'ô','œ', 'õ', 'ö', 'ø', 'ù', 'ú', 'û', 'ü', 'ÿ'])
  
      punctuation = ['&iquest;', '&iexcl;', '&laquo;', '&raquo;', '&sect;', 
      '&para;', '&dagger;', '&Dagger;', '&bull;', '&ndash;', '&mdash;']\
      .zip(['¿', '¡', '«', '»', '§', '¶', '†', '‡', '•', '–', '—'])
  
      commercial = ['&trade;', '&copy;', '&reg;', '&cent;', '&euro;', '&yen;',
      '&pound;', '&curren;'].zip(['™', '©', '®', '¢', '€', '¥', '£', '¤'])
  
      greek_chr = ['&alpha;', '&beta;', '&gamma;', '&delta;', '&epsilon;', 
      '&zeta;', '&eta;', '&theta;', '&iota;', '&kappa;', '&lambda;', '&mu;', 
      '&nu;', '&xi;', '&omicron;', '&pi;', '&rho;', '&sigma;', '&sigmaf;', 
      '&tau;', '&upsilon;', '&phi;', '&chi;', '&psi;', '&omega;', '&Gamma;', 
      '&Delta;', '&Theta;', '&Lambda;', '&Xi;', '&Pi;', '&Sigma;', '&Phi;', 
      '&Psi;', '&Omega;']\
      .zip(['α', 'β', 'γ', 'δ', 'ε', 'ζ', 'η', 'θ', 'ι', 'κ', 'λ', 
      'μ', 'ν', 'ξ', 'ο', 'π', 'ρ', 'σ', 'ς', 'τ', 'υ', 'φ', 'χ', 
      'ψ', 'ω', 'Γ', 'Δ', 'Θ', 'Λ', 'Ξ', 'Π', 'Σ', 'Φ', 'Ψ', 'Ω'])
  
      math_chr1 = ['&int;', '&sum;', '&prod;', '&radic;', '&minus;', '&plusmn;',
      '&infin;', '&asymp;', '&prop;', '&equiv;', '&ne;', '&le;', '&ge;', 
      '&times;', '&middot;', '&divide;', '&part;', '&prime;', '&Prime;', 
      '&nabla;', '&permil;', '&deg;', '&there4;', '&oslash;', '&isin;', '&cap;', 
      '&cup;', '&sub;', '&sup;', '&sube;', '&supe;', '&not;', '&and;', '&or;', 
      '&exist;', '&forall;', '&rArr;', '&hArr;', '&rarr;', '&harr;', '&uarr;']\
      .zip(['∫', '∑', '∏', '√', '−', '±', '∞', '≈', '∝', '≡', '≠', '≤', 
      '≥', '×', '·', '÷', '∂', '′', '″', '∇', '‰', '°', '∴', 'ø', '∈', 
      '∩', '∪', '⊂', '⊃', '⊆', '⊇', '¬', '∧', '∨', '∃', '∀', '⇒', 
      '⇔', '→', '↔', '↑'])
  
      math_chr2 = ['&alefsym;', '&notin;'].zip(['ℵ', '∉'])
  
      others = ['&uml;', '&ordf;', 
      '&macr;', '&acute;', '&micro;', '&cedil;', '&ordm;', '&lsquo;', '&rsquo;', 
      '&ldquo;', '&sbquo;', '&rdquo;', '&bdquo;', '&spades;', '&clubs;', '&loz;', 
      '&hearts;', '&larr;', '&diams;', '&lsaquo;', '&rsaquo;', '&darr;']\
      .zip(['¨', 'ª', '¯', '´', 'µ', '¸', 'º', '‘', '’', '“', '‚', '”', 
      '„', '♠', '♣', '◊', '♥', '←', '♦', '‹', '›', '↓'] )
  
      spc_array = html + umraut_accent + punctuation + commercial + greek_chr + 
                  math_chr1 + math_chr2 + others
      $sp_hash  = Hash[*spc_array.flatten]
      $sp_regex = Regexp.new("(" + $sp_hash.keys.join("|") + ")")
    end
    #str.gsub!("&amp;"){'&'}
    str.gsub!($sp_regex) do
      $sp_hash[$1]
    end
  end

  def remove_tag!(str, tagset = ['<', '>'])
    tagsets = Regexp.quote(tagset.uniq.join(""))
    regex = /#{Regexp.escape(tagset[0])}[^#{tagsets}]*#{Regexp.escape(tagset[1])}/
    str.gsub!(regex, "")
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

  def remove_directive!(str)
    remove_tag!(str, ['__', '__'])
  end
  
  def mndash!(str)
    str.gsub!($mndash_regex, "–")
  end

  def remove_hr!(page)
    page.gsub!($remove_hr_regex, "")
  end

  def make_reference!(str)
    str.gsub!($make_reference_regex_a, "\n")
    str.gsub!($make_reference_regex_b, "")
    str.gsub!($make_reference_regex_c, "[ref]")
    str.gsub!($make_reference_regex_d, "[/ref]")
  end

  def format_ref!(page)
    ###### do nothing for now
    # page.gsub!($format_ref_regex) do
    # end
  end

  def correct_inline_template!(str)
    str.gsub!($remove_inline_regex) do
      key = $1
      if $onset_bar_regex =~ key
        result = key
      elsif
        info = key.split("|")
        type_code = info.first
        case type_code
        when $type_code_regex
          out = info[-1]
        else
          if $leave_template
            out = "{" + info.collect{|i|i.chomp}.join("|") + "}"
          else
            out = ""
          end
        end
        out
      else
        ""
      end
    end
  end
  
  #################### methods currently unused ####################

  def process_template(str)
    scanner = StringScanner.new(str)
    result = process_nested_structure(scanner, "{{", "}}", $limit_recur) do |contents|
      parts = contents.split("|")
      case parts.size
      when 0
        ""
      when 1
        parts.first || ""
      else
        if parts.last.split("=").size > 1
          parts.first || ""
        else
          parts.last || ""
        end
      end
    end
    result
  end

  def remove_table(str)
    new_str = str.gsub($remove_table_regex, "")
    if str != new_str
      new_str = remove_table(new_str)
    end
    new_str = remove_table(new_str) unless str == new_str
    return new_str
  end
  
  def remove_clade(page)
    new_page = page.gsub($remove_clade_regex, "")
    new_page = remove_clade(new_page) unless page == new_page
    new_page
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

  def rename(files)    
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
      File.rename(f, newname + ".txt")
    end
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
