# frozen_string_literal: true

module Wp2txt
  # Regions whose contents are not parsed as article wikitext. Keep the same
  # recognition rules for lead terms and incoming links.
  module WikitextRegions
    TAGS = %w[nowiki pre math code syntaxhighlight source gallery score timeline chem ce graph mapframe].freeze
    COMMENT = /<!--.*?(?:-->|\z)/m
    REGION = /<!--.*?(?:-->|\z)|<(?<tag>#{TAGS.join('|')})(?=[\s\/>])(?:"[^"]*"|'[^']*'|[^'">])*?(?:\/>|>.*?(?:<\/\k<tag>\s*>|\z))/mi
    REGION_AT = /\G(?:#{REGION})/

    module_function

    def end_at(text, offset)
      match = REGION_AT.match(text, offset)
      match.end(0) if match
    end

    def remove(text)
      text.gsub(REGION, "")
    end

    # One space per codepoint, including internal newlines: an excluded
    # region must not introduce a paragraph or heading boundary.
    def mask(text)
      text.gsub(REGION) { |region| " " * region.length }
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
