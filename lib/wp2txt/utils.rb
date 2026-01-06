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
    # Reduce 3+ consecutive newlines to 2
    result.gsub!(CLEANUP_REGEX_08, "\n\n")
    # Also handle mixed whitespace patterns (spaces/tabs between newlines)
    result.gsub!(/\n[ \t]*\n[ \t]*\n+/, "\n\n")

    # Fix 1: Multiple consecutive spaces → single space (but preserve indentation at line start)
    result.gsub!(/([^\n]) {2,}/, '\1 ')

    # Fix 2: Empty parentheses → remove (both ASCII and Japanese)
    result.gsub!(/\(\s*\)/, "")
    result.gsub!(/（\s*）/, "")

    # Fix 3: Leftover pipe characters (table/infobox remnants)
    result.gsub!(/\|\|+/, "")           # Multiple pipes
    result.gsub!(/\|\s*$/, "")          # Trailing pipe at end of line
    result.gsub!(/^\s*\|[^|]*$\n?/m, "") # Lines that are just pipe + content (table rows)
    # Lines with multiple pipe-separated key=value pairs (infobox remnants)
    result.gsub!(/^\s*\|?\w+=[\w\s-]+(?:\|\w+=[\w\s-]+)+\s*$/m, "")
    # Template name remnants (standalone words like "Clearleft", "notelist2", "reflist")
    result.gsub!(/^\s*(?:Clearleft|Clear|notelist\d*|reflist|Reflist|Notelist|Commons\s*cat?)\s*$/im, "")
    # Imagemap/gallery remnants: lines like "Image:file.jpg|thumb|...|caption" without [[ brackets
    result.gsub!(/^(?:Image|File|Media|ファイル|画像|Datei|Fichier|Archivo):[^\n]+\|[^\n]+$/im, "")
    # Incomplete File/Image links (opened but not closed on same logical unit)
    result.gsub!(/\[\[(?:File|Image|Media|ファイル|画像|Datei|Fichier|Archivo):[^\]]*\|?\s*$/im, "")
    # Orphaned closing brackets from split File links (e.g., "caption]] rest of text")
    result.gsub!(/([^|\[\]]+)\]\]/, '\1')

    result.strip!
    result << "\n\n"
  end

  #################### parser for nested structure ####################

  # Optimized single-pass nested structure processor
  # Processes innermost brackets first, avoiding recursion overhead
  def process_nested_structure(scanner, left, right, &block)
    str = scanner.is_a?(StringScanner) ? scanner.string : scanner.to_s
    process_nested_single_pass(str, left, right, &block)
  end

  # Single-pass iterative processor - finds and processes innermost brackets first
  # This avoids the overhead of recursive calls and repeated string scanning
  def process_nested_single_pass(str, left, right, &block)
    return str unless str.include?(left)

    result = +str
    left_len = left.length
    right_len = right.length
    max_iterations = 50000  # Safety limit for deeply nested structures

    iterations = 0
    loop do
      iterations += 1
      break if iterations > max_iterations

      pos = 0
      found = false

      while pos < result.length
        # Find next left bracket
        left_pos = result.index(left, pos)
        break unless left_pos

        # Look for nested left bracket and matching right bracket
        inner_left = result.index(left, left_pos + left_len)
        right_pos = result.index(right, left_pos + left_len)

        break unless right_pos

        # If there's a nested left bracket before the right, skip to process inner first
        if inner_left && inner_left < right_pos
          pos = inner_left
          next
        end

        # Found innermost pair - process it
        content = result[(left_pos + left_len)...right_pos]
        processed = yield content
        result = result[0...left_pos] + processed + result[(right_pos + right_len)..]
        found = true
        break
      end

      break unless found
    end

    result
  rescue StandardError
    str
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

  # Simplified regex for common File/Image patterns (faster matching)
  FILE_NAMESPACES_QUICK_REGEX = /\A\s*(?:File|Image|Media|ファイル|画像|Datei|Fichier|Archivo)\s*:/i
  # Parameters to skip when extracting captions (use \A and \z for exact string match)
  FILE_PARAMS_REGEX = /\A(thumb|thumbnail|frame|frameless|border|right|left|center|none|upright|baseline|sub|super|top|text-top|middle|bottom|text-bottom)\z/i

  def process_interwiki_links(str)
    # Early exit if no links present
    return str unless str.include?("[[")

    process_nested_single_pass(str, "[[", "]]") do |contents|
      parts = contents.split("|")
      first_part = parts.first || ""

      if FILE_NAMESPACES_QUICK_REGEX.match?(first_part) || FILE_NAMESPACES_REGEX.match?(first_part)
        # For File/Image links, extract caption (last non-parameter part)
        # Normalize newlines to pipes (handles malformed markup with newlines instead of pipes)
        normalized = contents.gsub(/\n/, "|")
        parts = normalized.split("|")
        # Skip parts that look like parameters (contain =, or are size specs like 200px)
        if parts.size > 1
          caption = parts[1..].reverse.find do |p|
            stripped = p.strip
            !stripped.empty? && !stripped.include?("=") && !stripped.match?(/\A\d+px\z/i) && !FILE_PARAMS_REGEX.match?(stripped)
          end
          caption&.strip || ""
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
    # Early exit if no external links present
    return str unless str.include?("[")

    process_nested_single_pass(str, "[", "]") do |contents|
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
    # Early exit if no templates present
    return str unless str.include?("{{")

    result = process_nested_single_pass(str, "{{", "}}") { "" }

    # Handle single brace templates (less common)
    return result unless result.include?("{")
    process_nested_single_pass(result, "{", "}") { "" }
  end

  def remove_table(str)
    # Early exit if no tables present
    return str unless str.include?("{|")

    process_nested_single_pass(str, "{|", "|}") { "" }
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
      # Early exit if tag not present
      next unless res.include?("<#{tag}")
      result = process_nested_single_pass(res, "<#{tag}", "#{tag}>") { "" }
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

  # Templates that should be completely removed (citations, references, navigation)
  REMOVE_TEMPLATES_REGEX = /\A\s*(?:cite\s*(?:web|book|news|journal|magazine|conference|press|av\s*media|episode|map|sign|video|thesis)|sfn|efn|refn|reflist|refbegin|refend|notelist|r\||rp|main|see\s*also|further|details|about|redirect|distinguish|other\s*(?:uses|people)|for\s*(?:other|more)|hatnote|self-?reference|portal|commons|wiktionary|wikiquote|flagicon|flag|flagcountry|fb|noflag|country\s*data|small|smaller|large|larger|nbsp|thin\s*space|nowrap|clear|break|col-?(?:begin|end|break)|div\s*col|end\s*div|anchor|visible\s*anchor|unicode)\s*(?:\||$)/i

  # Country code templates (2-3 letter codes that represent flags)
  COUNTRY_CODE_REGEX = /\A[A-Z]{2,3}\z/

  def correct_inline_template(str)
    # Early exit if no templates present
    return str unless str.include?("{{")

    process_nested_single_pass(str, "{{", "}}") do |contents|
      parts = contents.split("|")
      template_name = (parts[0] || "").strip.downcase

      # Remove citation and navigation templates entirely
      if REMOVE_TEMPLATES_REGEX.match?(contents)
        ""
      # {{IPA|...}} or {{IPA-xx|...}} - keep the pronunciation (check BEFORE country codes)
      elsif template_name == "ipa" || template_name.start_with?("ipa-")
        (parts[1] || "").to_s.strip
      # Remove country code flag templates (JPN, USA, GBR, etc.)
      elsif COUNTRY_CODE_REGEX.match?(parts[0]&.strip || "")
        ""
      # Language templates: {{lang|code|text}} or {{lang-xx|text}}
      elsif template_name == "lang" || template_name == "fontsize"
        parts.size >= 3 ? parts[2].to_s.strip : (parts[1] || "").to_s.strip
      elsif template_name.start_with?("lang-")
        (parts[1] || "").to_s.strip
      # {{langwithname|code|name|text}} - extract the text (3rd param)
      elsif template_name == "langwithname"
        parts.size >= 4 ? parts[3].to_s.strip : (parts.last || "").to_s.strip
      # {{nihongo|text|kanji|romaji}} - format as "text (kanji, romaji)"
      elsif template_name == "nihongo"
        text = (parts[1] || "").strip
        kanji = (parts[2] || "").strip
        romaji = (parts[3] || "").strip
        if kanji.empty? && romaji.empty?
          text
        elsif romaji.empty?
          "#{text} (#{kanji})"
        elsif kanji.empty?
          "#{text} (#{romaji})"
        else
          "#{text} (#{kanji}, #{romaji})"
        end
      # {{仮リンク|display|lang|article}} - Japanese interwiki, keep display
      elsif template_name == "仮リンク"
        (parts[1] || "").to_s.strip
      # {{読み仮名|text|reading}} - format as "text（reading）"
      elsif template_name == "読み仮名"
        text = (parts[1] || "").strip
        reading = (parts[2] || "").strip
        reading.empty? ? text : "#{text}（#{reading}）"
      # {{convert|num|from|to}} - keep number and first unit
      elsif template_name == "convert"
        num = (parts[1] || "").strip
        unit = (parts[2] || "").strip
        unit.empty? ? num : "#{num} #{unit}"
      # Default handling for other templates
      else
        extract_template_content(parts)
      end
    end
  end

  # Extract meaningful content from template parts
  def extract_template_content(parts)
    return "" if parts.empty?
    return parts[0].to_s.strip if parts.size == 1

    # Skip the template name, try to find non-parameter content
    parts[1..].each do |part|
      next if part.nil?
      # Skip if it looks like a parameter (contains =)
      next if part.include?("=")
      content = part.strip
      return content unless content.empty?
    end

    # If all parts have =, try to extract value from first parameter
    parts[1..].each do |part|
      next if part.nil?
      if part.include?("=")
        key, value = part.split("=", 2)
        return value.to_s.strip unless value.nil? || value.strip.empty?
      end
    end

    ""
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
