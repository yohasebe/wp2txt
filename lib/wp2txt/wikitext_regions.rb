# frozen_string_literal: true

module Wp2txt
  # Literal regions suppress wikitext parsing. Galleries and timelines can
  # contain links, but their contents are not the article's lead prose.
  module WikitextRegions
    LITERAL_TAGS = %w[nowiki pre math chem ce score syntaxhighlight source graph mapframe templatedata].freeze
    NON_PROSE_TAGS = %w[gallery timeline].freeze
    COMMENT = /<!--.*?(?:-->|\z)/m

    def self.region_pattern(tags)
      /<!--.*?(?:-->|\z)|<(?<tag>#{tags.join('|')})(?=[\s\/>])(?:"[^"]*"|'[^']*'|[^'">])*?(?:\/>|>.*?(?:<\/\k<tag>\s*>|\z))/mi
    end

    LITERAL_REGION = region_pattern(LITERAL_TAGS)
    LEAD_REGION = region_pattern(LITERAL_TAGS + NON_PROSE_TAGS)
    LITERAL_REGION_AT = /\G(?:#{LITERAL_REGION})/
    LEAD_REGION_AT = /\G(?:#{LEAD_REGION})/

    module_function

    def end_at(text, offset, lead: false)
      match = (lead ? LEAD_REGION_AT : LITERAL_REGION_AT).match(text, offset)
      match.end(0) if match
    end

    def remove_literal(text)
      text.gsub(LITERAL_REGION, "")
    end

    # One space per codepoint, including internal newlines: an excluded
    # region must not introduce a paragraph or heading boundary.
    def mask_lead(text)
      text.gsub(LEAD_REGION) { |region| " " * region.length }
    end

    def split_pipes(text)
      parts = [+""]
      stack = []
      i = 0
      while i < text.length
        two = text[i, 2]
        if text[i] == "<" && (stop = end_at(text, i))
          parts.last << text[i...stop]
          i = stop
        elsif ["{{", "[["].include?(two)
          stack << (two == "{{" ? "}}" : "]]")
          parts.last << two
          i += 2
        elsif !stack.empty? && two == stack.last
          stack.pop
          parts.last << two
          i += 2
        else
          if text[i] == "|" && stack.empty?
            parts << +""
          else
            parts.last << text[i]
          end
          i += 1
        end
      end
      parts
    end
  end
end
