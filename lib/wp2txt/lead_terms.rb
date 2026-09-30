# frozen_string_literal: true

require_relative "wikitext_regions"

module Wp2txt
  # Finds the terms an article introduces in its lead: bold spans in the first
  # paragraph that has one, the parenthesized notes written right after each,
  # and reading (ruby) templates. Nothing is judged — which note is a reading,
  # a native spelling, or a date is left to the caller.
  #
  # Positions are character offsets [start, end) into the article's wikitext
  # as stored in the dump, XML entities decoded, before any other processing
  # (comments included), so a caller holding the same text can cut out and
  # hash exactly the span a term came from.
  module LeadTerms
    MAX_TERMS = 5
    HEADING = /^={2,6}[^=\n].*?={2,6}[ \t]*$/
    OPENERS = { "(" => ")", "（" => "）" }.freeze
    SEPARATORS = ["、", ",", "，", ";", "；"].freeze
    PARAGRAPH_BREAK = /\n[ \t\r]*\n/
    # Regions whose bold text is not the article's own lead prose
    SKIP_OPEN = { "{{" => "}}", "{|" => "|}", "<!--" => "-->" }.freeze
    REF_OPEN = /\A<ref(?:\s[^>]*)?>/i
    REF_SELF_CLOSING = /\A<ref(?:\s[^>]*)?\/>/i
    FILE_LINK = /\A\[\[\s*(?:file|image|ファイル|画像|media)\s*:/i

    module_function

    # @param wikitext [String] decoded article wikitext
    # @param render [#call] turns a wikitext fragment into clean text
    # @return [Array<Hash>] terms in order of appearance, at most MAX_TERMS
    def extract(wikitext, render:)
      return [] if wikitext.nil? || wikitext.empty?

      visible = WikitextRegions.mask_lead(wikitext)
      bolds, rubies, lead_end = scan(visible, visible.length, source: wikitext)
      original_render = render
      render = ->(fragment) { original_render.call(fragment.gsub(WikitextRegions::COMMENT, "")) }
      terms = []

      if (first = bolds.first)
        paragraph = paragraph_bounds(visible, first[0], lead_end)
        bolds.select { |s, e| s >= paragraph[0] && e <= paragraph[1] }.first(MAX_TERMS).each do |s, e|
          terms << bold_term(wikitext, s, e, paragraph[1], render)
        end
      end
      rubies.each do |s, e, parts|
        terms << { "text" => render.call(parts[1].to_s).strip, "reading" => render.call(parts[2].to_s).strip,
                   "source" => parts[0].strip, "span" => { "template" => [s, e] } }
      end

      terms.sort_by { |t| t["span"].values.first.first }.first(MAX_TERMS)
           .each_with_index.map { |t, i| { "index" => i }.merge(t) }
    end

    # Top-level bold spans [start, end) including the quote marks, and ruby
    # templates [start, end, [name, text, reading]] found in the lead
    def scan(text, limit, source: text)
      bolds = []
      rubies = []
      i = 0
      open_bold = nil
      while i < limit
        if (i.zero? || text[i - 1] == "\n") && text[i] == "=" &&
           HEADING.match?(text[i...(text.index("\n", i) || limit)])
          limit = i
          break
        elsif text[i] == "\n"
          open_bold = nil # bold does not continue across lines
          i += 1
        elsif (close = SKIP_OPEN[text[i, 4] == "<!--" ? "<!--" : text[i, 2]])
          opener = text[i, 4] == "<!--" ? "<!--" : text[i, 2]
          stop = matching_end(text, i, opener, close)
          if opener == "{{" && (ruby = ruby_template(source[(i + 2)...(stop - 2)]))
            rubies << [i, stop, ruby]
          end
          i = stop
        elsif text[i, 2] == "[[" && FILE_LINK.match?(text[i, 40])
          i = matching_end(text, i, "[[", "]]")
        elsif text[i] == "<" && (m = REF_SELF_CLOSING.match(text[i, 200]))
          i += m[0].length
        elsif text[i] == "<" && (m = REF_OPEN.match(text[i, 200]))
          close_at = text.index(%r{</ref\s*>}i, i + m[0].length)
          i = close_at ? text.index(">", close_at) + 1 : limit
        elsif text[i, 3] == "'''"
          run = text[i..][/\A'+/].length
          if open_bold
            bolds << [open_bold, i + run]
            open_bold = nil
          else
            open_bold = i
          end
          i += run
        else
          i += 1
        end
      end
      [bolds, rubies, limit]
    end

    # End index (exclusive) of the construct opened at start, honouring nesting
    def matching_end(text, start, opener, closer)
      depth = 0
      i = start
      while i < text.length
        if text[i, opener.length] == opener
          depth += 1
          i += opener.length
        elsif text[i, closer.length] == closer
          depth -= 1
          i += closer.length
          return i if depth.zero?
        else
          i += 1
        end
      end
      text.length
    end

    def ruby_template(content)
      parts = split_top_level(content, ["|"])
      name = parts.first.to_s
      return nil unless ruby_name?(name)

      [name, parts[1], parts[2]]
    end

    # Same name rule as the cleaner: "_" and " " alike, case-insensitive
    def ruby_name?(name)
      @ruby_names ||= Wp2txt::RUBY_TEXT_TEMPLATES.to_set { |t| t.tr("_", " ").strip.downcase }
      @ruby_names.include?(name.to_s.tr("_", " ").strip.downcase)
    end

    def paragraph_bounds(text, pos, limit)
      start = 0
      text[0...pos].to_enum(:scan, PARAGRAPH_BREAK).each { start = Regexp.last_match.end(0) }
      stop = text.index(PARAGRAPH_BREAK, pos) || limit
      [start, [stop, limit].min]
    end

    def bold_term(text, s, e, limit, render)
      inner = text[s...e].sub(/\A'+/, "").sub(/'+\z/, "")
      term = { "text" => render.call(plain_ruby(inner)).strip, "notes" => [], "notes_text" => nil,
               "source" => "bold", "span" => { "bold" => [s, e] } }
      j = e
      j += 1 while j < limit && [" ", "\t", "　", "\r", "\n"].include?(text[j])
      return term if j >= limit
      closer = OPENERS[text[j]]
      return term unless closer

      pe = paren_end(text, j, text[j], closer, limit)
      return term unless pe

      raw = text[(j + 1)...(pe - 1)]
      term["notes_text"] = render.call(raw).strip
      term["notes"] = split_top_level(raw, SEPARATORS).map { |part| render.call(part).strip }.reject(&:empty?)
      term["span"]["paren"] = [j, pe]
      term
    end

    # Index after the bracket closing the one at start, or nil if unclosed
    def paren_end(text, start, opener, closer, limit)
      depth = 0
      i = start
      while i < limit
        two = text[i, 2]
        if text[i] == "<" && (stop = WikitextRegions.end_at(text, i, lead: true))
          i = stop
          next
        elsif ["{{", "[["].include?(two)
          i = matching_end(text, i, two, two == "{{" ? "}}" : "]]")
          next
        end
        if [opener, "(", "（"].include?(text[i])
          depth += 1
        elsif [closer, ")", "）"].include?(text[i])
          depth -= 1
          return i + 1 if depth.zero?
        elsif text[i] == "\n" && /\A\n[ \t\r]*\n/.match?(text[i..])
          return nil
        end
        i += 1
      end
      nil
    end

    # Split at separators that sit outside brackets, templates, and links
    def split_top_level(text, separators)
      parts = [+""]
      depth = 0
      i = 0
      while i < text.length
        two = text[i, 2]
        if text[i] == "<" && (stop = WikitextRegions.end_at(text, i, lead: true))
          parts.last << text[i...stop]
          i = stop
        elsif ["{{", "[["].include?(two)
          depth += 1
          parts.last << two
          i += 2
        elsif ["}}", "]]"].include?(two)
          depth -= 1
          parts.last << two
          i += 2
        else
          ch = text[i]
          depth += 1 if ["(", "（"].include?(ch)
          depth -= 1 if [")", "）"].include?(ch)
          if depth <= 0 && separators.include?(ch)
            parts << +""
          else
            parts.last << ch
          end
          i += 1
        end
      end
      parts
    end

    # In a bold headword, a ruby template stands for its base text; the
    # reading is reported separately as its own term
    def plain_ruby(fragment)
      fragment.gsub(/\{\{([^{}]*)\}\}/) do |whole|
        (ruby = ruby_template(Regexp.last_match(1))) ? ruby[1].to_s : whole
      end
    end
  end
end
