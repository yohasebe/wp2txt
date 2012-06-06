#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'strscan'
require 'find'

module Wp2txt::TextUtils

  def format_wiki(text)
    text = special_chr(text)
    text = unbracket(text)

    text = remove_emphasis(text)
    text = chrref_to_utf(text)
    text = remove_inline_template(text)
    text = remove_directive(text)

    text = mndash(text)
    text = make_reference(text)
    text = format_ref(text)
    text = remove_table(text)
    text = remove_clade(text)
    text = remove_hr(text)
    text = remove_tag(text)
    
  end
  
  #################### methods used from format_wiki ####################

  def special_chr(str)
    unless @sp_hash 
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
      @sp_hash  = Hash[*spc_array.flatten]
      @sp_regex = Regexp.new("(" + @sp_hash.keys.join("|") + ")")
    end
    newstr = str.gsub(/&amp;/, '&')
    newstr.gsub!(@sp_regex) do
      @sp_hash[$1]
    end
    return newstr
  end

  def unbracket(str)
    unless @ub_regexes
    
      op_wbk   = '\[\['     #open double brackets
      cl_wbk   = '\]\]'     #close double brackets
      no_clbk  = '[^\[\]]' #character other than close bracket

      @ub_regexes = []
      #[[Image:xxx.jpg|thumb|240px|XXX] => ""
      @ub_regexes << /#{op_wbk}(?:Category|Image|File|画像|ファイル)\:#{no_clbk}*#{cl_wbk}/i
      # @ub_regexes << /\[\[#{no_clbk}+?\:#{no_clbk}*\]\]/i
      #[[内閣総理大臣の一覧|内閣総理大臣]] => 内閣総理大臣
      @ub_regexes << /#{op_wbk}#{no_clbk}+\|(#{no_clbk}+)#{cl_wbk}/
      #[[Wikipedia:井戸端|]] => 井戸端
      @ub_regexes << /#{op_wbk}#{no_clbk}+?:(#{no_clbk}+)\s*\|#{cl_wbk}/
      #[[Wiktionary:青]] => ""
      @ub_regexes << /#{op_wbk}(Wik#{no_clbk}+\:#{no_clbk}+)?#{cl_wbk}/
      #[[el:青]] => ""
      @ub_regexes << /#{op_wbk}#{no_clbk}+\:(?:#{no_clbk}*)#{cl_wbk}/
      #[[関数(数学)|]] => 関数
      @ub_regexes << /#{op_wbk}(#{no_clbk}+)\(#{no_clbk}+\)\s*\|#{cl_wbk}/
      #[[関数(数学)]] => 関数
      @ub_regexes << /#{op_wbk}(#{no_clbk}+)#{cl_wbk}/
      #[http://www.jpf.go.jp/j/japan_j/news/0407/07-01.html 国際交流基金調査] => 国際交流基金調査
      @ub_regexes << /\[http[!-~]+\s+([^\s]#{no_clbk}+)?\]/
      #[http://europa.eu.int/comm/internal_market/copyright/docs/review/sec-2004-995_en.pdf] => ""
      @ub_regexes << /\[http#{no_clbk}+\]/
      # [xxx] = ""
      @ub_regexes << /\[#{no_clbk}+?\]/
    end
    new_str = str.dup
    @ub_regexes.each do |regex|
      new_str.gsub!(regex) do
        $1
      end
    end
    new_str = unbracket(new_str) unless str == new_str  
    return new_str
  end

  def remove_tag(str, tagset = ['<', '>'])
    tagsets = Regexp.quote(tagset.uniq.join(""))
    regex = /#{tagset[0]}[^#{tagsets}]*#{tagset[1]}/
    newstr = str.gsub(regex, "")
    # newstr = newstr.gsub(/<\!\-\-.*?\-\->/, "")
    return newstr
  end

  def remove_emphasis(str)
    str.gsub(/(''+)(.+?)\1/) do
      $2
    end
  end

  def chrref_to_utf(num_str)
    begin
      utf_str = num_str.gsub(/&#(x?)([0-9a-fA-F]+);/) do
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
      return num_str
    end
    return utf_str
  end

  def remove_inline_template(str)
    str.gsub(/\{\{(.*?)\}\}/) do
       key = $1
       if /\A[^\|]+\z/ =~ key
         result = key
       else
         info = key.split("|")
         type_code = info.first
         case type_code
         when /\Alang*/i, /\AIPA/i, /\AIEP/i, /\ASEP/i, /\Aindent/i, /\Aaudio/i, /\Asmall/i, 
              /\Admoz/i, /\Apron/i, /\Aunicode/i, /\Anote label/i, /\Anowrap/i, 
              /\AArabDIN/i, /\Atrans/i, /\ANihongo/i, /\APolytonic/i
           out = info[-1]
         else
           out = "{" + info.collect{|i|i.chomp}.join("|") + "}"
         end
         result = out
       end
     end
  end

  def remove_directive(str)
    remove_tag(str, ['__', '__'])
  end
  
  def mndash(str)
    str = str.gsub(/\{(mdash|ndash|\–)\}/, "–")
  end

  def make_reference(str)
    new_str = str.dup
    new_str.gsub!(/<br ?\/>/, "\n")
    new_str.gsub!(/<ref[^>]*\/>/, "")
    new_str.gsub!(/<ref[^>]*>/, "[ref]")
    new_str.gsub!(/<\/ref>/, "[/ref]")
    return new_str
  end

  def format_ref(page)
    page = page.gsub(/\[ref\](.*?)\[\/ref\]/m) do
      ref = $1.dup
      "[ref]" + ref.gsub(/(?:[\r\n]+|<br ?\/>)/, " ") + "[/ref]"     
    end
  end

  def remove_table(str)
    new_str = str.gsub(/\{\|.*?\|\}/m, "")    
    if str != new_str
      new_str = remove_table(new_str)
    end
    new_str = remove_table(new_str) unless str == new_str
    return new_str
  end
    
  def remove_clade(page)
    new_page = page.gsub(/\{\{(?:C|c)lade[^\{\}]*\}\}/m, "")
    new_page = remove_clade(new_page) unless page == new_page
    new_page
  end

  def remove_hr(page)
    page = page.gsub(/^\s*\-+\s*$/m, "")
  end
  
  #################### methods currently unused ####################

  def remove_inside_paren(str)
    new_str = str.gsub(/\s*(?:\(|（)[^\(\)（）]*(?:\)|）)/, "")
    if str != new_str
      new_str = remove_inside_paren(new_str)
    end
    return new_str
  end
  
  def remove_refs(str)
    new_str = str.gsub(/\[ref\].*?\[\/ref\]/m, "")
  end

  # separate strings into sentences every time a (kind of) period
  # is encountered
  def punctuate(text)
    
    # inside brackets (and the like), sentence does not end but continues
    brackets = [['（', '）'],
    ['【', '】'],
    ['〔', '〕'],
    ['［', '］'],
    ['｛', '｝'],
    ['〈', '〉'],
    ['《', '》'],
    ['\(', '\)'],
    ['\[', '\]'],
    ['「', '」'],
    ['『', '』'],
    ]

    result = Array.new
    scanner = StringScanner.new(text)
    regex = Regexp.new(/.*?。/)
    
    while scanner.scan(regex)
      temp ||= ""; temp << scanner.matched
      num_of_open  = 0
      num_of_close = 0
      
      brackets.each do |bracket|
        open  = bracket[0]
        close = bracket[1]
        num_of_open  += temp.scan(/#{open}/).length
        num_of_close += temp.scan(/#{close}/).length
      end

      # if the numbers of open/close brackets do not match, go next iteration
      # and concatenate another line of text
      next if num_of_open > num_of_close
      
      # yield to do something like getting rid of annotations if necessary
      yield [temp] if block_given?
 
      temp.gsub!(/^[\s　]*(.*?)[\s　]*$/) {$1}
      result << temp
      temp = ""
    end
    
    return result
  end

  # throw away text inside parentheses
  def delete_annotation(sentence)
    annotation = [['（', '）']]
    
    annotation.each_with_index do |bracket, index|
      open  = bracket[0]
      close = bracket[1]
      anno_regex = /#{open}[^#{open}#{close}]+?#{close}/
      # loop to take care of nested parentheses
      while sentence.gsub!(anno_regex, "") do 
      end
    end
    return sentence
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
