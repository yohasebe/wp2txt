#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

module WikipediaUtils
  
  def mndash(str)
    str = str.gsub(/\{(mdash|ndash|\–)\}/, "–")
  end
  
  def preprocess(page)
    page = special_chr(page)
    page = mndash(page)
    page = make_reference(page)
    page = format_ref(page)
    page = remove_image(page)
    page = remove_table(page)
    page = remove_clade(page)
  end
  
  def format_ref(page)
    page = page.gsub(/\[ref\](.*?)\[\/ref\]/m) do
      ref = $1.dup
      "[ref]" + ref.gsub(/(?:[\r\n]+|<br ?\/>)/, " ") + "[/ref]"     
    end
  end
  
  def remove_clade(page)
    new_page = page.gsub(/\{\{(?:C|c)lade[^\{\}]*\}\}/m, "")
    new_page = remove_clade(new_page) unless page == new_page
    new_page
  end
  
  def format_wiki(text)
    fcontents = remove_emphasis(text)
    fcontents = chrref_to_utf(fcontents)
    fcontents = unbracket(fcontents)
    # fcontents = make_referencece(fcontents)
    fcontents = remove_html(fcontents)
    fcontents = remove_pagename(fcontents)
    fcontents = remove_directive(fcontents)
    return fcontents
  end

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

  def remove_table(str)
    new_str = str.gsub(/\{\|.*?\|\}/m, "")    
    if str != new_str
      new_str = remove_table(new_str)
    end
    new_str = remove_table(new_str) unless str == new_str
    return new_str
  end
  
  def remove_image(str)
    str.gsub(/\[\[(?:Image|File|画像|ファイル)\:[^\[\]]+\]\]/m, "")
  end

  def cleanup_text(str, remove_paren = false, remove_bracket = true)
    if remove_bracket
      str = remove_refs(str)
    end
    if remove_paren
      str = remove_inside_paren(str)
    else
      str = str.gsub("()", "")
    end
    str = str.gsub(/\n\s*\n\n+/, "\n\n")
  end

  def make_reference(str)
    new_str = str.dup
    new_str.gsub!(/<br ?\/>/, "\n")
    new_str.gsub!(/<ref[^>]*\/>/, "")
    new_str.gsub!(/<ref[^>]*>/, "[ref]")
    new_str.gsub!(/<\/ref>/, "[/ref]")
    return new_str
  end
  
  def remove_tag(str, tagset = ['<', '>'])
    tagsets = Regexp.quote(tagset.uniq.join(""))
    regex = /#{tagset[0]}[^#{tagsets}]*#{tagset[1]}/
    newstr = str.gsub(regex, "")
    return newstr
  end

  def remove_html(str)
    remove_tag(str)
  end

  def remove_pagename(str)
    str.gsub(/\{\{(.*?)\}\}/) do
       info = $1.split("|")
       type_code = info.first
       case type_code
       when /\Alang*/i, /\AIPA/i, /\AIEP/i, /\ASEP/i, /\Aindent/i, /\Aaudio/i, /\Asmall/i, 
            /\Admoz/i, /\Apron/i, /\Aunicode/i, /\Anote label/i, /\Anowrap/i, 
            /\AArabDIN/i, /\Atrans/i, /\ANihongo/i, /\APolytonic/i
         out = info[-1]
       else
         out = "{" + info.collect{|i|i.chomp}.join("|") + "}"
       end
       out
     end
  end
  
  def remove_directive(str)
    remove_tag(str, ['__', '__'])
  end
  
  def remove_emphasis(str)
    str.gsub(/(''+)(.+?)\1/) do
      $2
    end
  end

  def remove_sources(str)
    str.gsub(/<source ?.*>.*<\/source>/m, "")
  end

  def unbracket(str)
    unless @ub_regexes
    
      op_wbk   = '\[\['     #open double brackets
      cl_wbk   = '\]\]'     #close double brackets
      no_clbk  = '[^\[\]]' #character other than close bracket

      @ub_regexes = []
      #[[Image:xxx.jpg|thumb|240px|XXX] => ""
      @ub_regexes << /\[\[(?:Image|File|画像|ファイル)\:[^\[\]]*\]\]/i
      #[[Wikipedia:井戸端|]] => 井戸端
      @ub_regexes << /#{op_wbk}#{no_clbk}+?:(#{no_clbk}+)\s*\|#{cl_wbk}/
      #[[関数(数学)|]] => 関数
      @ub_regexes << /#{op_wbk}(#{no_clbk}+)\(#{no_clbk}+\)\s*\|#{cl_wbk}/
      #[[内閣総理大臣の一覧|内閣総理大臣]] => 内閣総理大臣
      @ub_regexes << /#{op_wbk}#{no_clbk}+\|(#{no_clbk}+)#{cl_wbk}/
      #[[関数(数学)|]] => 関数
      @ub_regexes << /#{op_wbk}(#{no_clbk}+)#{cl_wbk}/
      #[http://www.jpf.go.jp/j/japan_j/news/0407/07-01.html 国際交流基金調査] => 国際交流基金調査
      @ub_regexes << /\[http[!-~]+\s+([^\s][^\[\]]+)?\]/
      #[http://europa.eu.int/comm/internal_market/copyright/docs/review/sec-2004-995_en.pdf] => ""
      @ub_regexes << /\[http[^\[\]]+\]/
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
  
  module_function :special_chr
end
