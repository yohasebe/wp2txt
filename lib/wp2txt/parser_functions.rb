# frozen_string_literal: true

module Wp2txt
  # Evaluates MediaWiki parser functions
  # Handles #if, #ifeq, #switch, #expr, #ifexpr, and string functions
  class ParserFunctions
    MONTH_NAMES = %w[
      January February March April May June
      July August September October November December
    ].freeze

    def initialize(reference_date: nil, preserve_unknown: false)
      @reference_date = reference_date || Time.now
      @preserve_unknown = preserve_unknown
    end

    # Main evaluation method
    def evaluate(text)
      return text if text.nil? || text.empty?

      result = text.dup

      # Process parser functions from innermost to outermost
      max_iterations = 10
      iteration = 0

      while result.include?("{{#") && iteration < max_iterations
        previous = result.dup
        result = evaluate_single_pass(result)
        break if result == previous
        iteration += 1
      end

      result
    end

    private

    def evaluate_single_pass(text)
      result = +""
      pos = 0

      while pos < text.length
        start_idx = text.index("{{#", pos)

        if start_idx.nil?
          result << text[pos..]
          break
        end

        # Add text before parser function
        result << text[pos...start_idx]

        # Find matching }}
        end_idx = find_template_end(text, start_idx + 2)

        if end_idx.nil?
          result << text[start_idx..]
          break
        end

        content = text[(start_idx + 2)...end_idx]
        expanded = evaluate_parser_function(content)
        result << expanded

        pos = end_idx + 2
      end

      result
    end

    def find_template_end(text, start_pos)
      depth = 1
      pos = start_pos

      while pos < text.length - 1
        if text[pos, 2] == "{{"
          depth += 1
          pos += 2
        elsif text[pos, 2] == "}}"
          depth -= 1
          return pos if depth.zero?
          pos += 2
        else
          pos += 1
        end
      end

      nil
    end

    def evaluate_parser_function(content)
      # Parse function name and arguments
      # Content starts with # (e.g., "#if:condition|then|else")
      return "" unless content.start_with?("#")

      # Find function name (up to first : or |)
      colon_idx = content.index(":")
      return "" if colon_idx.nil?

      function_name = content[1...colon_idx].downcase
      args_str = content[(colon_idx + 1)..]
      args = split_arguments(args_str)

      case function_name
      when "if"
        evaluate_if(args)
      when "ifeq"
        evaluate_ifeq(args)
      when "iferror"
        evaluate_iferror(args)
      when "switch"
        evaluate_switch(args)
      when "ifexpr"
        evaluate_ifexpr(args)
      when "expr"
        evaluate_expr(args)
      when "len"
        evaluate_len(args)
      when "pos"
        evaluate_pos(args)
      when "rpos"
        evaluate_rpos(args)
      when "count"
        evaluate_count(args)
      when "sub"
        evaluate_sub(args)
      when "replace"
        evaluate_replace(args)
      when "explode"
        evaluate_explode(args)
      when "urldecode"
        evaluate_urldecode(args)
      when "urlencode"
        evaluate_urlencode(args)
      when "padleft"
        evaluate_padleft(args)
      when "padright"
        evaluate_padright(args)
      when "titleparts"
        evaluate_titleparts(args)
      when "time"
        evaluate_time(args)
      else
        @preserve_unknown ? "{{##{content}}}" : ""
      end
    end

    def split_arguments(str)
      args = []
      current = +""
      depth = 0

      str.each_char do |c|
        case c
        when "{", "["
          depth += 1
          current << c
        when "}", "]"
          depth -= 1
          current << c
        when "|"
          if depth.zero?
            args << current
            current = +""
          else
            current << c
          end
        else
          current << c
        end
      end

      args << current
      args
    end

    # #if: condition | then | else
    def evaluate_if(args)
      return "" if args.empty?

      condition = args[0]&.strip || ""
      then_value = args[1] || ""
      else_value = args[2] || ""

      if condition.empty?
        else_value
      else
        then_value
      end
    end

    # #ifeq: value1 | value2 | then | else
    def evaluate_ifeq(args)
      return "" if args.length < 2

      value1 = args[0]&.strip || ""
      value2 = args[1]&.strip || ""
      then_value = args[2] || ""
      else_value = args[3] || ""

      # Try numeric comparison first
      if numeric?(value1) && numeric?(value2)
        equal = value1.to_f == value2.to_f
      else
        equal = value1 == value2
      end

      equal ? then_value : else_value
    end

    # #switch: value | case1=result1 | case2=result2 | #default=default
    def evaluate_switch(args)
      return "" if args.empty?

      value = args[0]&.strip || ""
      cases = args[1..]
      default = ""
      pending_cases = []

      cases.each do |case_arg|
        if case_arg.include?("=")
          key, result = case_arg.split("=", 2)
          key = key.strip

          if key == "#default"
            default = result
          elsif key == value || pending_cases.include?(value)
            return result
          end
          pending_cases.clear
        else
          # Fall-through case
          trimmed = case_arg.strip
          if trimmed == value
            pending_cases << trimmed
          else
            pending_cases << trimmed
            # Last unnamed value becomes default
            default = case_arg.strip
          end
        end
      end

      default
    end

    # #ifexpr: expression | then | else
    def evaluate_ifexpr(args)
      return "" if args.empty?

      expr_str = args[0] || ""
      then_value = args[1] || ""
      else_value = args[2] || ""

      result = calculate_expression(expr_str)
      return else_value if result.nil?

      result != 0 ? then_value : else_value
    end

    # #expr: expression
    def evaluate_expr(args)
      return "" if args.empty?

      expr_str = args[0] || ""
      result = calculate_expression(expr_str)
      return "" if result.nil?

      # Format result
      if result == result.to_i && !expr_str.include?("/")
        result.to_i.to_s
      elsif result == result.to_i
        result.to_i.to_s
      else
        format("%.2f", result).sub(/0+$/, "").sub(/\.$/, "")
      end
    end

    def calculate_expression(expr_str)
      # Normalize expression
      expr = expr_str.strip
      return nil if expr.empty?

      # Check if expression contains logical operators
      has_logical = expr.match?(/\b(and|or|not)\b/i)

      # Replace MediaWiki operators with Ruby equivalents
      expr = expr.gsub(/\bmod\b/i, " % ")
      expr = expr.gsub("^", "**")

      # Handle single = as equality (MediaWiki style)
      # Be careful not to replace ==, <=, >=, !=
      expr = expr.gsub(/(?<![=!<>])=(?!=)/, "==")

      # Convert integers to floats for division
      expr = expr.gsub(/\b(\d+)\b/) { "#{$1}.0" }

      # For logical operators, convert numbers to booleans (0 = false, non-zero = true)
      if has_logical
        # Convert "X and Y" to "(X != 0) && (Y != 0) ? 1 : 0" style
        # But simpler: replace and/or/not to work on != 0 comparison
        expr = expr.gsub(/\band\b/i, "!= 0.0 && ")
        expr = expr.gsub(/\bor\b/i, "!= 0.0 || ")
        expr = expr.gsub(/\bnot\b/i, "== 0.0 ||")
        # Add trailing != 0 for the last operand
        expr = "(#{expr} != 0.0 ? 1.0 : 0.0)"
      end

      # Evaluate safely
      begin
        # Only allow safe characters (numbers, operators, parentheses, whitespace, ?)
        return nil unless expr.match?(/\A[\d\s\+\-\*\/\%\(\)\.\<\>\=\!\&\|\?:]+\z/)

        result = eval(expr)

        # Convert boolean results to 1/0
        case result
        when true then 1.0
        when false then 0.0
        else result.to_f
        end
      rescue StandardError
        nil
      end
    end

    def numeric?(str)
      !!(str =~ /\A-?\d+\.?\d*\z/)
    end

    # #len: string
    def evaluate_len(args)
      str = args[0] || ""
      str.length.to_s
    end

    # #pos: string | search
    def evaluate_pos(args)
      str = args[0] || ""
      search = args[1] || ""
      pos = str.index(search)
      pos.nil? ? "" : pos.to_s
    end

    # #sub: string | start | length
    def evaluate_sub(args)
      str = args[0] || ""
      start = (args[1] || "0").to_i
      length = args[2]&.to_i

      if length
        str[start, length] || ""
      else
        str[start..] || ""
      end
    end

    # #replace: string | search | replace
    def evaluate_replace(args)
      str = args[0] || ""
      search = args[1] || ""
      replace = args[2] || ""
      str.gsub(search, replace)
    end

    # #rpos: string | search (find last occurrence)
    def evaluate_rpos(args)
      str = args[0] || ""
      search = args[1] || ""
      pos = str.rindex(search)
      pos.nil? ? "-1" : pos.to_s
    end

    # #count: string | search (count occurrences)
    def evaluate_count(args)
      str = args[0] || ""
      search = args[1] || ""
      return "0" if search.empty?
      # Non-overlapping count
      str.scan(search).length.to_s
    end

    # #explode: string | delimiter | index
    def evaluate_explode(args)
      str = args[0] || ""
      delimiter = args[1] || ""
      index = (args[2] || "0").to_i

      parts = str.split(delimiter)
      return "" if parts.empty?

      # Handle negative index (from end)
      if index.negative?
        index = parts.length + index
      end

      return "" if index < 0 || index >= parts.length
      parts[index] || ""
    end

    # #urldecode: string
    def evaluate_urldecode(args)
      str = args[0] || ""
      require "cgi"
      CGI.unescape(str)
    end

    # #urlencode: string
    def evaluate_urlencode(args)
      str = args[0] || ""
      require "uri"
      URI.encode_www_form_component(str).gsub("+", "%20")
    end

    # #padleft: string | length | padding
    def evaluate_padleft(args)
      str = args[0] || ""
      length = (args[1] || "0").to_i
      padding = args[2] || " "
      padding = " " if padding.empty?

      return str if str.length >= length
      (padding * ((length - str.length) / padding.length + 1))[0, length - str.length] + str
    end

    # #padright: string | length | padding
    def evaluate_padright(args)
      str = args[0] || ""
      length = (args[1] || "0").to_i
      padding = args[2] || " "
      padding = " " if padding.empty?

      return str if str.length >= length
      str + (padding * ((length - str.length) / padding.length + 1))[0, length - str.length]
    end

    # #iferror: input | then | else
    def evaluate_iferror(args)
      input = args[0] || ""
      then_value = args[1]
      else_value = args[2] || ""

      # Check for error indicators
      has_error = input.include?('class="error"') ||
                  input.include?("class='error'") ||
                  input.match?(/Expression error/i)

      if has_error
        then_value || ""
      elsif then_value.nil?
        input
      else
        else_value
      end
    end

    # #titleparts: title | parts | offset
    def evaluate_titleparts(args)
      title = args[0] || ""
      parts_count = (args[1] || "0").to_i
      offset = (args[2] || "0").to_i

      # Split by / but keep namespace prefix with first part
      segments = title.split("/")
      return title if segments.empty?

      # Apply offset
      if offset.positive?
        segments = segments[offset..] || []
      elsif offset.negative?
        segments = segments[0...offset] || []
      end

      # Apply parts count
      if parts_count.positive?
        segments = segments[0, parts_count]
      elsif parts_count.negative?
        segments = segments[0...parts_count]
      end

      segments.join("/")
    end

    # #time: format | date
    def evaluate_time(args)
      format_str = args[0] || ""
      date_str = args[1]

      time = if date_str && !date_str.strip.empty?
               parse_date(date_str.strip)
             else
               @reference_date
             end

      return "" unless time

      format_time(time, format_str)
    end

    def parse_date(str)
      # Try common formats
      formats = ["%Y-%m-%d", "%Y/%m/%d", "%d %B %Y", "%B %d, %Y"]

      formats.each do |fmt|
        return Time.strptime(str, fmt)
      rescue ArgumentError
        next
      end

      nil
    end

    DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

    def format_time(time, format_str)
      result = +""
      i = 0

      while i < format_str.length
        c = format_str[i]
        next_c = format_str[i + 1]

        # Handle two-character sequences
        if c == "j" && next_c == "S"
          result << time.day.to_s << ordinal_suffix(time.day)
          i += 2
          next
        end

        result << case c
                  # Year
                  when "Y" then time.year.to_s
                  when "y" then (time.year % 100).to_s.rjust(2, "0")
                  # Month
                  when "m" then time.month.to_s.rjust(2, "0")
                  when "n" then time.month.to_s
                  when "F" then MONTH_NAMES[time.month - 1]
                  when "M" then MONTH_NAMES[time.month - 1][0, 3]
                  # Day
                  when "d" then time.day.to_s.rjust(2, "0")
                  when "j" then time.day.to_s
                  when "S" then ordinal_suffix(time.day)
                  # Day of week
                  when "l" then DAY_NAMES[time.wday]
                  when "D" then DAY_NAMES[time.wday][0, 3]
                  when "N" then (time.wday == 0 ? 7 : time.wday).to_s
                  when "w" then time.wday.to_s
                  # Week
                  when "W" then time.strftime("%V")
                  # Hour
                  when "H" then time.hour.to_s.rjust(2, "0")
                  when "G" then time.hour.to_s
                  when "g" then (time.hour % 12 == 0 ? 12 : time.hour % 12).to_s
                  when "h" then (time.hour % 12 == 0 ? 12 : time.hour % 12).to_s.rjust(2, "0")
                  # Minute/Second
                  when "i" then time.min.to_s.rjust(2, "0")
                  when "s" then time.sec.to_s.rjust(2, "0")
                  # AM/PM
                  when "a" then time.hour < 12 ? "am" : "pm"
                  when "A" then time.hour < 12 ? "AM" : "PM"
                  # Timezone
                  when "T" then time.strftime("%Z")
                  when "O" then time.strftime("%z")
                  # Unix timestamp
                  when "U" then time.to_i.to_s
                  else c
                  end
        i += 1
      end

      result
    end

    def ordinal_suffix(day)
      if (11..13).include?(day % 100)
        "th"
      else
        case day % 10
        when 1 then "st"
        when 2 then "nd"
        when 3 then "rd"
        else "th"
        end
      end
    end
  end
end
