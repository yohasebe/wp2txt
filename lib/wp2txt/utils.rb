# frozen_string_literal: true

require "strscan"
require_relative "constants"
require_relative "regex"
require_relative "text_processing"
require_relative "file_utils"
require_relative "magic_words"
require_relative "template_expander"
require_relative "parser_functions"

module Wp2txt
  # Main wiki formatting utilities: format_wiki, markers, templates, links

  # Marker types for special content
  MARKER_TYPES = %i[math code chem table score timeline graph ipa infobox navbox gallery sidebar mapframe imagemap references codeblock].freeze

  # Inline markers: removing these can break surrounding text
  INLINE_MARKERS = %i[math chem ipa code].freeze

  # Block markers: these are standalone and can be safely removed
  BLOCK_MARKERS = %i[table score timeline graph infobox navbox gallery sidebar mapframe imagemap references codeblock].freeze

  # Default: all markers enabled
  DEFAULT_MARKERS = MARKER_TYPES.dup.freeze

  # Regex patterns for marker detection
  MARKER_PATTERNS = {
    # MATH: <math>...</math>, {{math|...}}, {{mvar|...}}
    math: {
      tags: [/<math[^>]*>.*?<\/math>/mi],
      templates: [/\{\{(?:math|mvar)\s*\|/i]
    },
    # CODE: <code>...</code> (inline only)
    code: {
      tags: [
        /<code[^>]*>.*?<\/code>/mi
      ],
      templates: []
    },
    # CODEBLOCK: <syntaxhighlight>...</syntaxhighlight>, <source>...</source>, <pre>...</pre> (block)
    codeblock: {
      tags: [
        /<syntaxhighlight[^>]*>.*?<\/syntaxhighlight>/mi,
        /<source[^>]*>.*?<\/source>/mi,
        /<pre[^>]*>.*?<\/pre>/mi
      ],
      templates: []
    },
    # CHEM: <chem>...</chem>, {{chem|...}}, {{ce|...}}
    chem: {
      tags: [/<chem[^>]*>.*?<\/chem>/mi],
      templates: [/\{\{(?:chem|ce)\s*\|/i]
    },
    # TABLE: {|...|}, <table>...</table>
    table: {
      tags: [/<table[^>]*>.*?<\/table>/mi],
      wiki_table: true
    },
    # SCORE: <score>...</score>
    score: {
      tags: [/<score[^>]*>.*?<\/score>/mi],
      templates: []
    },
    # TIMELINE: <timeline>...</timeline>
    timeline: {
      tags: [/<timeline[^>]*>.*?<\/timeline>/mi],
      templates: []
    },
    # GRAPH: <graph>...</graph>
    graph: {
      tags: [/<graph[^>]*>.*?<\/graph>/mi],
      templates: []
    },
    # IPA: {{IPA|...}}, {{IPAc-en|...}}, etc.
    ipa: {
      tags: [],
      templates: [/\{\{IPA[c]?(?:-[a-z]{2,3})?\s*\|/i]
    },
    # INFOBOX: {{Infobox ...}}
    infobox: {
      tags: [],
      templates: [/\{\{[Ii]nfobox\s*/]
    },
    # NAVBOX: {{Navbox ...}}
    navbox: {
      tags: [],
      templates: [/\{\{[Nn]avbox\s*/]
    },
    # GALLERY: <gallery>...</gallery>
    gallery: {
      tags: [/<gallery[^>]*>.*?<\/gallery>/mi],
      templates: []
    },
    # SIDEBAR: {{Sidebar ...}}
    sidebar: {
      tags: [],
      templates: [/\{\{[Ss]idebar\s*/]
    },
    # MAPFRAME: <mapframe>...</mapframe>
    mapframe: {
      tags: [/<mapframe[^>]*>.*?<\/mapframe>/mi],
      templates: []
    },
    # IMAGEMAP: <imagemap>...</imagemap>
    imagemap: {
      tags: [/<imagemap[^>]*>.*?<\/imagemap>/mi],
      templates: []
    },
    # REFERENCES: {{reflist}}, {{refbegin}}...{{refend}}, <references/>
    references: {
      tags: [
        /<references\s*\/>/mi,
        /<references[^>]*>.*?<\/references>/mi
      ],
      templates: [/\{\{[Rr]eflist\s*/],
      paired_templates: [{ start: /\{\{[Rr]efbegin/i, end_name: "refend" }]
    }
  }.freeze

  def format_wiki(text, config = {})
    # Work with a mutable copy to reduce intermediate string allocations
    result = +text.to_s

    # Early exit: Skip expensive processing if no templates present
    has_templates = result.include?("{{")

    # Expand magic words if title is provided and text contains templates
    # This converts {{PAGENAME}}, {{CURRENTYEAR}}, {{lc:...}}, etc. to actual values
    if config[:title] && has_templates
      magic_expander = MagicWordExpander.new(
        config[:title],
        namespace: config[:namespace] || "",
        dump_date: config[:dump_date]
      )
      result = magic_expander.expand(result)
    end

    # Expand parser functions if enabled and text contains parser function syntax
    # This evaluates {{#if:...}}, {{#switch:...}}, {{#expr:...}}, etc.
    if config[:expand_templates] && has_templates && result.include?("{{#")
      parser_functions = ParserFunctions.new(
        reference_date: config[:dump_date]
      )
      result = parser_functions.evaluate(result)
    end

    # Expand common templates if enabled and text still contains templates
    # This converts {{birth date|...}}, {{convert|...}}, etc. to readable text
    if config[:expand_templates] && result.include?("{{")
      template_expander = TemplateExpander.new(
        reference_date: config[:dump_date]
      )
      result = template_expander.expand(result)
    end

    # CPU-intensive regex processing (can be parallelized with Ractor)
    result = format_wiki_regex_transform(result, config)

    # Decode HTML entities (e.g., &Oslash; → Ø)
    # This uses HTMLEntities gem - must be done outside Ractor
    result = special_chr(result)

    # Convert marker placeholders to final [MARKER] format
    result = finalize_markers(result)
    result
  end

  # CPU-intensive regex transformations - Ractor-safe (no external gem dependencies)
  # This is the part that benefits from parallel processing
  def format_wiki_regex_transform(text, config = {})
    result = +text.to_s

    # Determine which markers are enabled
    markers_config = config.fetch(:markers, true)
    enabled_markers = parse_markers_config(markers_config)

    # Citation extraction option
    extract_citations = config.fetch(:extract_citations, false)

    # Apply markers BEFORE other processing (to preserve content for replacement)
    markers_to_apply = extract_citations ? enabled_markers - [:references] : enabled_markers
    result = apply_markers(result, markers_to_apply)

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

    result = correct_inline_template(result, enabled_markers, extract_citations) unless config[:inline]
    result = remove_templates(result) unless config[:inline]
    result = remove_table(result, enabled_markers) unless config[:table]

    result
  end

  # Parse markers configuration
  # true or nil: all markers enabled
  # false: no markers
  # Array: only specified markers
  def parse_markers_config(config)
    case config
    when true, nil
      DEFAULT_MARKERS.dup
    when false
      []
    when Array
      config.map(&:to_sym) & MARKER_TYPES
    else
      DEFAULT_MARKERS.dup
    end
  end

  # Placeholder format for markers (to avoid conflicts with bracket processing)
  # These get converted to [MARKER] at the end of format_wiki
  def marker_placeholder(type)
    "\u00AB\u00AB#{type.to_s.upcase}\u00BB\u00BB"  # «« MARKER »»
  end

  # Convert marker placeholders to final [MARKER] format
  def finalize_markers(str)
    result = +str.to_s
    MARKER_TYPES.each do |marker_type|
      placeholder = marker_placeholder(marker_type)
      final_marker = "[#{marker_type.to_s.upcase}]"
      result.gsub!(placeholder, final_marker)
    end
    result
  end

  # Apply marker replacements for enabled marker types
  # When markers are disabled, content is removed (not marked)
  def apply_markers(str, enabled_markers)
    result = +str.to_s

    MARKER_PATTERNS.each do |marker_type, patterns|
      placeholder = marker_placeholder(marker_type)
      should_mark = enabled_markers.include?(marker_type)

      # Process HTML-style tags
      patterns[:tags]&.each do |tag_regex|
        if should_mark
          result.gsub!(tag_regex, placeholder)
        else
          # Remove content when marker is not enabled
          result.gsub!(tag_regex, "")
        end
      end

      # Process wiki tables specially (need nested handling)
      if patterns[:wiki_table] && result.include?("{|")
        if should_mark
          result = replace_wiki_table_with_marker(result, placeholder)
        end
        # If not marking, remove_table will handle it later
      end

      # Process template-based markers (Infobox, Navbox, Sidebar)
      patterns[:templates]&.each do |template_regex|
        result = replace_template_with_marker(result, template_regex, placeholder, should_mark)
      end

      # Process paired templates (refbegin...refend)
      patterns[:paired_templates]&.each do |pair|
        result = replace_paired_templates_with_marker(result, pair[:start], pair[:end_name], placeholder, should_mark)
      end
    end

    result
  end

  # Replace paired templates like {{refbegin}}...{{refend}} with marker
  # When should_mark is false, skip processing entirely (don't remove content)
  # This allows extract_citations to process the inner templates
  def replace_paired_templates_with_marker(str, start_pattern, end_name, placeholder, should_mark)
    return str unless should_mark  # Skip if not marking - let content be processed later

    result = +str.to_s
    end_regex = /\{\{#{Regexp.escape(end_name)}\s*\}\}/i

    loop do
      match = result.match(start_pattern)
      break unless match

      start_pos = match.begin(0)

      # Find the closing template (e.g., {{refend}})
      end_match = result.match(end_regex, start_pos)
      break unless end_match

      end_pos = end_match.end(0)

      result = result[0...start_pos] + placeholder + result[end_pos..]
    end
    result
  end

  # Replace templates matching pattern with marker (handles nested braces)
  def replace_template_with_marker(str, pattern, placeholder, should_mark)
    result = +str.to_s
    # Find all positions where template pattern matches
    loop do
      match = result.match(pattern)
      break unless match

      start_pos = match.begin(0)
      # Find the end of this template by counting braces
      depth = 0
      pos = start_pos
      template_end = nil

      while pos < result.length
        if result[pos, 2] == "{{"
          depth += 1
          pos += 2
        elsif result[pos, 2] == "}}"
          depth -= 1
          pos += 2
          if depth == 0
            template_end = pos
            break
          end
        else
          pos += 1
        end
      end

      if template_end
        if should_mark
          result = result[0...start_pos] + placeholder + result[template_end..]
        else
          result = result[0...start_pos] + result[template_end..]
        end
      else
        # Unclosed template, break to avoid infinite loop
        break
      end
    end
    result
  end

  # Replace wiki tables {|...|} with marker
  def replace_wiki_table_with_marker(str, placeholder)
    return str unless str.include?("{|")
    process_nested_single_pass(str, "{|", "|}") { placeholder }
  end

  #################### link processing ####################

  # File/Image namespace and parameter regexes are now defined in regex.rb
  # FILE_NAMESPACES_REGEX - matches file namespace prefixes (313 aliases from 350+ languages)
  # IMAGE_PARAMS_REGEX - matches image parameters like thumb, right, left, etc.

  def process_interwiki_links(str)
    # Early exit if no links present
    return str unless str.include?("[[")

    process_nested_single_pass(str, "[[", "]]") do |contents|
      # Use -1 to preserve trailing empty strings (for pipe trick detection)
      parts = contents.split("|", -1)
      first_part = parts.first || ""

      # Category links should be removed entirely (categories are extracted separately)
      if CATEGORY_NAMESPACE_REGEX.match?(first_part)
        ""
      elsif FILE_NAMESPACES_REGEX.match?(first_part)
        # For File/Image links, extract caption (last non-parameter part)
        # Normalize newlines to pipes (handles malformed markup with newlines instead of pipes)
        normalized = contents.gsub(/\n/, "|")
        parts = normalized.split("|", -1)
        # Skip parts that look like parameters (contain =, or are size specs like 200px)
        if parts.size > 1
          caption = parts[1..].reverse.find do |p|
            stripped = p.strip
            !stripped.empty? && !stripped.include?("=") && !stripped.match?(/\A\d+px\z/i) && !(IMAGE_PARAMS_REGEX && IMAGE_PARAMS_REGEX.match?(stripped))
          end
          caption&.strip || ""
        else
          ""
        end
      elsif parts.size == 1
        first_part
      elsif parts.size == 2 && parts[1].strip.empty?
        # Pipe trick: [[Namespace:Page|]] or [[Page (disambiguation)|]]
        apply_pipe_trick(first_part)
      else
        parts.shift
        parts.join("|")
      end
    end
  end

  # MediaWiki pipe trick: extracts display text from link target
  # [[Wikipedia:著作権|]] → 著作権
  # [[東京 (曖昧さ回避)|]] → 東京
  def apply_pipe_trick(target)
    result = target.dup
    # Remove namespace prefix (everything before and including the last colon)
    result = result.sub(/\A[^:]+:/, "") if result.include?(":")
    # Remove trailing parenthetical (disambiguation)
    result = result.sub(/\s*\([^)]+\)\s*\z/, "")
    # Remove trailing comma and following text (for names like "LastName, FirstName")
    result = result.sub(/\s*,.*\z/, "")
    result.strip
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

  #################### template processing ####################

  def remove_templates(str)
    # Early exit if no templates present
    return str unless str.include?("{{")

    result = process_nested_single_pass(str, "{{", "}}") { "" }

    # Handle single brace templates (less common)
    return result unless result.include?("{")
    process_nested_single_pass(result, "{", "}") { "" }
  end

  def remove_table(str, enabled_markers = [])
    # Early exit if no tables present
    return str unless str.include?("{|")

    # If table marker is enabled, tables are already replaced with [TABLE]
    # Only remove if marker is not enabled
    if enabled_markers.include?(:table)
      str
    else
      process_nested_single_pass(str, "{|", "|}") { "" }
    end
  end

  # Citation templates that can be extracted
  # Data source: template_aliases.json (citation_templates category)
  CITATION_TEMPLATES = Wp2txt.load_template_data["citation_templates"] || []
  CITATION_TEMPLATE_REGEX = if CITATION_TEMPLATES.empty?
    # Fallback to basic pattern
    /\A\s*(?:cite\s*(?:web|book|news|journal)|citation)\s*(?:\||$)/i
  else
    pattern = CITATION_TEMPLATES.map { |t| Regexp.escape(t) }.join("|")
    Regexp.new('\A\s*(?:' + pattern + ')\s*(?:\||$)', Regexp::IGNORECASE)
  end

  # Templates that should be completely removed (references, navigation, but NOT citations when extracting)
  # Data source: template_aliases.json (remove_templates category)
  REMOVE_TEMPLATES = Wp2txt.load_template_data["remove_templates"] || []
  REMOVE_TEMPLATES_REGEX = if REMOVE_TEMPLATES.empty?
    # Fallback to basic pattern
    /\A\s*(?:sfn|efn|refn|reflist|notelist|main|see\s*also|portal)\s*(?:\||$)/i
  else
    pattern = REMOVE_TEMPLATES.map { |t| Regexp.escape(t) }.join("|")
    Regexp.new('\A\s*(?:' + pattern + ')\s*(?:\||$)', Regexp::IGNORECASE)
  end

  # Flag templates to remove
  # Data source: template_aliases.json (flag_templates category)
  FLAG_TEMPLATES = Wp2txt.load_template_data["flag_templates"] || []
  FLAG_TEMPLATE_REGEX = if FLAG_TEMPLATES.empty?
    /\A\s*(?:flag|flagicon|flagcountry)\s*(?:\||$)/i
  else
    pattern = FLAG_TEMPLATES.map { |t| Regexp.escape(t) }.join("|")
    Regexp.new('\A\s*(?:' + pattern + ')\s*(?:\||$)', Regexp::IGNORECASE)
  end

  # Formatting templates (extract content)
  # Data source: template_aliases.json (formatting_templates category)
  FORMATTING_TEMPLATES = Wp2txt.load_template_data["formatting_templates"] || []
  FORMATTING_TEMPLATE_REGEX = if FORMATTING_TEMPLATES.empty?
    /\A\s*(?:small|smaller|large|larger|nowrap|nbsp)\s*(?:\||$)/i
  else
    pattern = FORMATTING_TEMPLATES.map { |t| Regexp.escape(t) }.join("|")
    Regexp.new('\A\s*(?:' + pattern + ')\s*(?:\||$)', Regexp::IGNORECASE)
  end

  # Ruby text templates (読み仮名 equivalent across languages)
  # Data source: template_aliases.json (ruby_text_templates category)
  RUBY_TEXT_TEMPLATES = Wp2txt.load_template_data["ruby_text_templates"] || []

  # Interwiki link templates (仮リンク equivalent across languages)
  # Data source: template_aliases.json (interwiki_link_templates category)
  INTERWIKI_LINK_TEMPLATES = Wp2txt.load_template_data["interwiki_link_templates"] || []

  # Mixed script templates (nihongo equivalent across languages)
  # Data source: template_aliases.json (mixed_script_templates category)
  MIXED_SCRIPT_TEMPLATES = Wp2txt.load_template_data["mixed_script_templates"] || []

  # Convert templates
  # Data source: template_aliases.json (convert_templates category)
  CONVERT_TEMPLATES = Wp2txt.load_template_data["convert_templates"] || []

  # Country code templates (2-3 letter codes that represent flags)
  COUNTRY_CODE_REGEX = /\A[A-Z]{2,3}\z/

  # Extract formatted citation from template parameters
  def format_citation(contents)
    params = {}
    contents.split("|").each do |part|
      if part.include?("=")
        key, value = part.split("=", 2)
        params[key.strip.downcase] = value&.strip
      end
    end

    # Extract author (last name, or author field)
    author = params["last"] || params["last1"] || params["author"] || params["author1"] || ""
    first = params["first"] || params["first1"] || ""
    author = "#{author}, #{first}" if !author.empty? && !first.empty?

    # Extract title
    title = params["title"] || ""

    # Extract year/date
    year = params["year"] || ""
    if year.empty? && params["date"]
      # Extract year from date like "2021-05-15"
      year = params["date"][0, 4] if params["date"] =~ /^\d{4}/
    end

    # Format: "Author. Title. Year." or partial if fields missing
    parts = []
    parts << author unless author.empty?
    parts << "\"#{title}\"" unless title.empty?
    parts << year unless year.empty?

    parts.empty? ? "" : parts.join(". ") + "."
  end

  # Helper to check if template name matches any in a list (case-insensitive)
  def template_matches?(name, template_list)
    return false if template_list.nil? || template_list.empty?
    normalized_name = name.to_s.strip.downcase
    template_list.any? { |t| t.downcase == normalized_name }
  end

  def correct_inline_template(str, enabled_markers = [], extract_citations = false)
    # Early exit if no templates present
    return str unless str.include?("{{")

    process_nested_single_pass(str, "{{", "}}") do |contents|
      parts = contents.split("|")
      template_name = (parts[0] || "").strip
      template_name_lower = template_name.downcase

      # =========================================================================
      # Specific template handlers (order matters - check before generic patterns)
      # =========================================================================

      # {{IPA|...}} or {{IPA-xx|...}} or {{IPAc-xx|...}}
      # Must be checked BEFORE mixed_script_templates which also contains IPA
      if template_name_lower == "ipa" || template_name_lower.start_with?("ipa-") || template_name_lower.start_with?("ipac-")
        if enabled_markers.include?(:ipa)
          marker_placeholder(:ipa)
        else
          (parts[1] || "").to_s.strip
        end
      # Language templates: {{lang|code|text}} or {{lang-xx|text}}
      # Must be checked BEFORE mixed_script_templates which also contains lang
      elsif template_name_lower == "lang"
        parts.size >= 3 ? parts[2].to_s.strip : (parts[1] || "").to_s.strip
      elsif template_name_lower.start_with?("lang-")
        (parts[1] || "").to_s.strip
      elsif template_name_lower == "fontsize"
        parts.size >= 3 ? parts[2].to_s.strip : (parts[1] || "").to_s.strip
      # {{langwithname|code|name|text}} - extract the text (3rd param)
      elsif template_name_lower == "langwithname"
        parts.size >= 4 ? parts[3].to_s.strip : (parts.last || "").to_s.strip
      # {{math|...}} or {{mvar|...}} - mathematical notation
      elsif template_name_lower == "math" || template_name_lower == "mvar"
        if enabled_markers.include?(:math)
          marker_placeholder(:math)
        else
          (parts[1] || "").to_s.strip
        end
      # {{chem|...}} or {{ce|...}} - chemical formulas
      elsif template_name_lower == "chem" || template_name_lower == "ce"
        if enabled_markers.include?(:chem)
          marker_placeholder(:chem)
        else
          (parts[1] || "").to_s.strip
        end

      # =========================================================================
      # Data-driven template matching (generic patterns from template_aliases.json)
      # =========================================================================

      # Handle citation templates
      elsif CITATION_TEMPLATE_REGEX.match?(contents)
        if extract_citations
          format_citation(contents)
        else
          ""
        end
      # Remove navigation/reference templates entirely
      elsif REMOVE_TEMPLATES_REGEX.match?(contents)
        ""
      # Remove flag templates (data-driven)
      elsif FLAG_TEMPLATE_REGEX.match?(contents) || COUNTRY_CODE_REGEX.match?(template_name)
        ""
      # Ruby text templates: 読み仮名, ruby, etc. (data-driven)
      elsif template_matches?(template_name, RUBY_TEXT_TEMPLATES)
        text = (parts[1] || "").strip
        reading = (parts[2] || "").strip
        reading.empty? ? text : "#{text}（#{reading}）"
      # Interwiki link templates: 仮リンク, ill, interlanguage link (data-driven)
      elsif template_matches?(template_name, INTERWIKI_LINK_TEMPLATES)
        # First parameter is display text
        (parts[1] || "").to_s.strip
      # Mixed script templates: nihongo, transl, etc. (data-driven)
      elsif template_matches?(template_name, MIXED_SCRIPT_TEMPLATES)
        # Format depends on template type
        if template_name_lower == "nihongo" || template_name_lower.start_with?("nihongo")
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
        elsif template_name_lower == "transl" || template_name_lower == "transliteration"
          # {{transl|lang|text}} -> text
          (parts[2] || parts[1] || "").to_s.strip
        else
          # Default: extract first content parameter
          (parts[1] || "").to_s.strip
        end
      # Convert templates (data-driven)
      elsif template_matches?(template_name, CONVERT_TEMPLATES)
        num = (parts[1] || "").strip
        unit = (parts[2] || "").strip
        unit.empty? ? num : "#{num} #{unit}"
      # Formatting templates: small, nowrap, nbsp, etc. (data-driven)
      elsif FORMATTING_TEMPLATE_REGEX.match?(contents)
        if template_name_lower == "nbsp"
          " "  # Non-breaking space
        else
          # Extract content from formatting template
          (parts[1] || "").to_s.strip
        end
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

  # =========================================================================
  # Make constants Ractor-shareable for parallel processing
  # =========================================================================
  module_function

  def self.make_constants_ractor_shareable!
    return unless defined?(Ractor) && Ractor.respond_to?(:make_shareable)

    constants(false).each do |const_name|
      const = const_get(const_name)
      next if Ractor.shareable?(const)

      begin
        Ractor.make_shareable(const)
      rescue Ractor::IsolationError, FrozenError, TypeError
        # Some constants can't be made shareable, skip them
      end
    end
  end

  make_constants_ractor_shareable!
end
