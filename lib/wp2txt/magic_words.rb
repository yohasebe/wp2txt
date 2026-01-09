# frozen_string_literal: true

require_relative "regex"

module Wp2txt
  # Expands MediaWiki magic words to their actual values
  # Supports: page context variables, date/time variables, string functions
  class MagicWordExpander
    # Page context magic words (case-insensitive)
    PAGE_CONTEXT_WORDS = {
      "PAGENAME" => :pagename,
      "PAGENAMEE" => :pagename_encoded,
      "FULLPAGENAME" => :fullpagename,
      "FULLPAGENAMEE" => :fullpagename_encoded,
      "BASEPAGENAME" => :basepagename,
      "BASEPAGENAMEE" => :basepagename_encoded,
      "ROOTPAGENAME" => :rootpagename,
      "ROOTPAGENAMEE" => :rootpagename_encoded,
      "SUBPAGENAME" => :subpagename,
      "SUBPAGENAMEE" => :subpagename_encoded,
      "TALKPAGENAME" => :talkpagename,
      "TALKPAGENAMEE" => :talkpagename_encoded,
      "SUBJECTPAGENAME" => :subjectpagename,
      "SUBJECTPAGENAMEE" => :subjectpagename_encoded,
      "ARTICLEPAGENAME" => :subjectpagename,
      "ARTICLEPAGENAMEE" => :subjectpagename_encoded,
      "NAMESPACE" => :namespace,
      "NAMESPACEE" => :namespace_encoded,
      "NAMESPACENUMBER" => :namespace_number,
      "TALKSPACE" => :talkspace,
      "TALKSPACEE" => :talkspace_encoded,
      "SUBJECTSPACE" => :subjectspace,
      "SUBJECTSPACEE" => :subjectspace_encoded,
      "ARTICLESPACE" => :subjectspace,
      "ARTICLESPACEE" => :subjectspace_encoded
    }.freeze

    # Date/time magic words
    DATETIME_WORDS = {
      "CURRENTYEAR" => :current_year,
      "CURRENTMONTH" => :current_month,
      "CURRENTMONTH1" => :current_month1,
      "CURRENTMONTHNAME" => :current_month_name,
      "CURRENTMONTHNAMEGEN" => :current_month_name,
      "CURRENTMONTHABBREV" => :current_month_abbrev,
      "CURRENTDAY" => :current_day,
      "CURRENTDAY2" => :current_day2,
      "CURRENTDOW" => :current_dow,
      "CURRENTDAYNAME" => :current_day_name,
      "CURRENTTIME" => :current_time,
      "CURRENTHOUR" => :current_hour,
      "CURRENTWEEK" => :current_week,
      "CURRENTTIMESTAMP" => :current_timestamp,
      # Local variants (same as current for our purposes)
      "LOCALYEAR" => :current_year,
      "LOCALMONTH" => :current_month,
      "LOCALMONTH1" => :current_month1,
      "LOCALMONTHNAME" => :current_month_name,
      "LOCALMONTHNAMEGEN" => :current_month_name,
      "LOCALMONTHABBREV" => :current_month_abbrev,
      "LOCALDAY" => :current_day,
      "LOCALDAY2" => :current_day2,
      "LOCALDOW" => :current_dow,
      "LOCALDAYNAME" => :current_day_name,
      "LOCALTIME" => :current_time,
      "LOCALHOUR" => :current_hour,
      "LOCALWEEK" => :current_week,
      "LOCALTIMESTAMP" => :current_timestamp
    }.freeze

    # String function magic words (with arguments)
    STRING_FUNCTIONS = %w[
      lc uc lcfirst ucfirst
      padleft padright
      anchorencode urlencode
      plural grammar gender
      int formatnum
    ].freeze

    # Month names for expansion
    MONTH_NAMES = %w[
      January February March April May June
      July August September October November December
    ].freeze

    MONTH_ABBREVS = %w[
      Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec
    ].freeze

    DAY_NAMES = %w[
      Sunday Monday Tuesday Wednesday Thursday Friday Saturday
    ].freeze

    def initialize(title, namespace: "", dump_date: nil)
      @title = title || ""
      @namespace = namespace || ""
      @dump_date = dump_date || Time.now
    end

    # Main expansion method - expands all supported magic words in text
    def expand(text)
      return text if text.nil? || text.empty?

      result = text.dup

      # Expand simple magic words: {{PAGENAME}}, {{CURRENTYEAR}}, etc.
      result = expand_simple_magic_words(result)

      # Expand string functions: {{lc:Text}}, {{uc:Text}}, etc.
      result = expand_string_functions(result)

      # Expand #titleparts parser function
      result = expand_titleparts(result)

      result
    end

    private

    # Expand simple magic words without arguments
    def expand_simple_magic_words(text)
      # Match {{WORD}} pattern (case-insensitive for the word)
      text.gsub(/\{\{\s*([A-Z][A-Z0-9]*)\s*\}\}/i) do |match|
        word = $1.upcase
        if PAGE_CONTEXT_WORDS.key?(word)
          expand_page_context(PAGE_CONTEXT_WORDS[word])
        elsif DATETIME_WORDS.key?(word)
          expand_datetime(DATETIME_WORDS[word])
        else
          match # Return unchanged if not recognized
        end
      end
    end

    # Expand page context magic words
    def expand_page_context(type)
      case type
      when :pagename
        @title
      when :pagename_encoded
        url_encode(@title)
      when :fullpagename
        @namespace.empty? ? @title : "#{@namespace}:#{@title}"
      when :fullpagename_encoded
        url_encode(@namespace.empty? ? @title : "#{@namespace}:#{@title}")
      when :basepagename
        # Remove subpage part (after last /)
        @title.sub(%r{/[^/]*$}, "")
      when :basepagename_encoded
        url_encode(@title.sub(%r{/[^/]*$}, ""))
      when :rootpagename
        # Get root page (before first /)
        @title.split("/").first || @title
      when :rootpagename_encoded
        url_encode(@title.split("/").first || @title)
      when :subpagename
        # Get subpage part (after last /)
        @title.include?("/") ? @title.split("/").last : @title
      when :subpagename_encoded
        part = @title.include?("/") ? @title.split("/").last : @title
        url_encode(part)
      when :talkpagename
        ns = @namespace.empty? ? "Talk" : "#{@namespace} talk"
        "#{ns}:#{@title}"
      when :talkpagename_encoded
        ns = @namespace.empty? ? "Talk" : "#{@namespace}_talk"
        url_encode("#{ns}:#{@title}")
      when :subjectpagename
        @namespace.empty? ? @title : "#{@namespace}:#{@title}"
      when :subjectpagename_encoded
        url_encode(@namespace.empty? ? @title : "#{@namespace}:#{@title}")
      when :namespace
        @namespace
      when :namespace_encoded
        url_encode(@namespace)
      when :namespace_number
        # Main namespace = 0, others would need a lookup table
        @namespace.empty? ? "0" : ""
      when :talkspace
        @namespace.empty? ? "Talk" : "#{@namespace} talk"
      when :talkspace_encoded
        url_encode(@namespace.empty? ? "Talk" : "#{@namespace} talk")
      when :subjectspace
        @namespace
      when :subjectspace_encoded
        url_encode(@namespace)
      else
        ""
      end
    end

    # Expand date/time magic words
    def expand_datetime(type)
      case type
      when :current_year
        @dump_date.year.to_s
      when :current_month
        @dump_date.month.to_s.rjust(2, "0")
      when :current_month1
        @dump_date.month.to_s
      when :current_month_name
        MONTH_NAMES[@dump_date.month - 1]
      when :current_month_abbrev
        MONTH_ABBREVS[@dump_date.month - 1]
      when :current_day
        @dump_date.day.to_s
      when :current_day2
        @dump_date.day.to_s.rjust(2, "0")
      when :current_dow
        @dump_date.wday.to_s
      when :current_day_name
        DAY_NAMES[@dump_date.wday]
      when :current_time
        @dump_date.strftime("%H:%M")
      when :current_hour
        @dump_date.hour.to_s.rjust(2, "0")
      when :current_week
        @dump_date.strftime("%V")
      when :current_timestamp
        @dump_date.strftime("%Y%m%d%H%M%S")
      else
        ""
      end
    end

    # Expand string functions: {{lc:Text}}, {{uc:Text}}, etc.
    def expand_string_functions(text)
      # Match {{function:argument}} pattern
      # Need to handle nested braces carefully
      result = text.dup

      # Simple string case functions (no nesting issues)
      result.gsub!(/\{\{\s*lc\s*:\s*([^}]*)\}\}/i) { $1.downcase }
      result.gsub!(/\{\{\s*uc\s*:\s*([^}]*)\}\}/i) { $1.upcase }
      result.gsub!(/\{\{\s*lcfirst\s*:\s*([^}]*)\}\}/i) do
        s = $1
        s.empty? ? s : s[0].downcase + s[1..]
      end
      result.gsub!(/\{\{\s*ucfirst\s*:\s*([^}]*)\}\}/i) do
        s = $1
        s.empty? ? s : s[0].upcase + s[1..]
      end

      # URL encoding
      result.gsub!(/\{\{\s*urlencode\s*:\s*([^}|]*?)(?:\s*\|\s*[^}]*)?\}\}/i) do
        url_encode($1.strip)
      end
      result.gsub!(/\{\{\s*anchorencode\s*:\s*([^}]*)\}\}/i) do
        anchor_encode($1.strip)
      end

      # Padding functions: {{padleft:string|length|pad}}
      result.gsub!(/\{\{\s*padleft\s*:\s*([^}|]*)\s*\|\s*(\d+)(?:\s*\|\s*([^}]*))?\}\}/i) do
        str, len, pad = $1, $2.to_i, ($3 || "0")
        pad = "0" if pad.empty?
        str.rjust(len, pad)
      end
      result.gsub!(/\{\{\s*padright\s*:\s*([^}|]*)\s*\|\s*(\d+)(?:\s*\|\s*([^}]*))?\}\}/i) do
        str, len, pad = $1, $2.to_i, ($3 || "0")
        pad = "0" if pad.empty?
        str.ljust(len, pad)
      end

      # formatnum - just return the number as-is (locale formatting would need more work)
      result.gsub!(/\{\{\s*formatnum\s*:\s*([^}|]*?)(?:\s*\|[^}]*)?\}\}/i) { $1.strip }

      # plural, grammar, gender - just return first argument (proper handling would need language rules)
      result.gsub!(/\{\{\s*plural\s*:\s*[^}|]*\s*\|\s*([^}|]*)[^}]*\}\}/i) { $1 }
      result.gsub!(/\{\{\s*grammar\s*:\s*[^}|]*\s*\|\s*([^}|]*)[^}]*\}\}/i) { $1 }
      result.gsub!(/\{\{\s*gender\s*:\s*[^}|]*\s*\|\s*([^}|]*)[^}]*\}\}/i) { $1 }

      # int - internationalization, just return the message name
      result.gsub!(/\{\{\s*int\s*:\s*([^}|]*)[^}]*\}\}/i) { $1.strip }

      result
    end

    # Expand #titleparts parser function
    # {{#titleparts:pagename|number of segments|first segment}}
    def expand_titleparts(text)
      text.gsub(/\{\{\s*#titleparts\s*:\s*([^}|]+)(?:\s*\|\s*([^}|]*))?(?:\s*\|\s*([^}]*))?\}\}/i) do
        pagename = $1.strip
        num_segments = $2&.strip&.to_i
        first_segment = ($3&.strip&.to_i || 1)

        parts = pagename.split("/")
        first_segment = 1 if first_segment < 1
        first_idx = first_segment - 1

        if num_segments && num_segments > 0
          parts[first_idx, num_segments]&.join("/") || ""
        elsif num_segments && num_segments < 0
          # Negative means "all but last N"
          end_idx = parts.length + num_segments
          end_idx > first_idx ? parts[first_idx...end_idx].join("/") : ""
        else
          parts[first_idx..]&.join("/") || ""
        end
      end
    end

    # URL encode a string (for PAGENAMEE variants)
    def url_encode(str)
      return "" if str.nil?

      str.gsub(/[^a-zA-Z0-9\-._~]/) do |c|
        c == " " ? "_" : "%" + c.unpack1("H*").upcase
      end
    end

    # Anchor encode (for fragment identifiers)
    def anchor_encode(str)
      return "" if str.nil?

      str.gsub(" ", "_").gsub(/[^\w\-.]/) do |c|
        ".#{c.unpack1('H*').upcase}"
      end
    end
  end
end
