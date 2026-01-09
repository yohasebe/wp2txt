# frozen_string_literal: true

module Wp2txt
  # Expands common MediaWiki templates to their text representation
  # Handles date templates, convert templates, and other common patterns
  class TemplateExpander
    MONTH_NAMES = %w[
      January February March April May June
      July August September October November December
    ].freeze

    # Unit conversion factors
    CONVERSIONS = {
      # Length
      ["km", "mi"] => 0.621371,
      ["mi", "km"] => 1.60934,
      ["m", "ft"] => 3.28084,
      ["ft", "m"] => 0.3048,
      ["cm", "in"] => 0.393701,
      ["in", "cm"] => 2.54,
      ["mm", "in"] => 0.0393701,
      ["in", "mm"] => 25.4,
      ["yd", "m"] => 0.9144,
      ["m", "yd"] => 1.09361,
      # Weight
      ["kg", "lb"] => 2.20462,
      ["lb", "kg"] => 0.453592,
      ["g", "oz"] => 0.035274,
      ["oz", "g"] => 28.3495,
      ["t", "lb"] => 2204.62,
      ["lb", "t"] => 0.000453592,
      # Temperature (special handling)
      ["C", "F"] => :celsius_to_fahrenheit,
      ["°C", "°F"] => :celsius_to_fahrenheit,
      ["F", "C"] => :fahrenheit_to_celsius,
      ["°F", "°C"] => :fahrenheit_to_celsius,
      # Area
      ["km2", "sqmi"] => 0.386102,
      ["sqmi", "km2"] => 2.58999,
      ["ha", "acre"] => 2.47105,
      ["acre", "ha"] => 0.404686,
      ["m2", "sqft"] => 10.7639,
      ["sqft", "m2"] => 0.092903,
      # Speed
      ["km/h", "mph"] => 0.621371,
      ["mph", "km/h"] => 1.60934,
      ["m/s", "km/h"] => 3.6,
      ["km/h", "m/s"] => 0.277778,
      # Volume
      ["l", "gal"] => 0.264172,
      ["gal", "l"] => 3.78541,
      ["ml", "floz"] => 0.033814,
      ["floz", "ml"] => 29.5735
    }.freeze

    # Unit display names
    UNIT_DISPLAY = {
      "km" => "km",
      "mi" => "mi",
      "m" => "m",
      "ft" => "ft",
      "cm" => "cm",
      "in" => "in",
      "mm" => "mm",
      "yd" => "yd",
      "kg" => "kg",
      "lb" => "lb",
      "g" => "g",
      "oz" => "oz",
      "t" => "t",
      "C" => "°C",
      "°C" => "°C",
      "F" => "°F",
      "°F" => "°F",
      "km2" => "km²",
      "sqmi" => "sq mi",
      "ha" => "ha",
      "acre" => "acres",
      "m2" => "m²",
      "sqft" => "sq ft",
      "km/h" => "km/h",
      "mph" => "mph",
      "m/s" => "m/s",
      "l" => "L",
      "gal" => "gal",
      "ml" => "mL",
      "floz" => "fl oz"
    }.freeze

    def initialize(reference_date: nil, preserve_unknown: false)
      @reference_date = reference_date || Time.now
      @preserve_unknown = preserve_unknown
    end

    # Main expansion method
    def expand(text)
      return text if text.nil? || text.empty?

      result = text.dup

      # Process templates from innermost to outermost
      max_iterations = 10
      iteration = 0

      while result.include?("{{") && iteration < max_iterations
        previous = result.dup
        result = expand_templates_single_pass(result)
        break if result == previous
        iteration += 1
      end

      result
    end

    private

    def expand_templates_single_pass(text)
      result = +""
      pos = 0

      while pos < text.length
        start_idx = text.index("{{", pos)

        if start_idx.nil?
          result << text[pos..]
          break
        end

        # Add text before template
        result << text[pos...start_idx]

        # Find matching }}
        end_idx = find_template_end(text, start_idx + 2)

        if end_idx.nil?
          # No matching }}, treat as plain text
          result << text[start_idx..]
          break
        end

        template_content = text[(start_idx + 2)...end_idx]
        expanded = expand_single_template(template_content)
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
          return pos if depth == 0
          pos += 2
        else
          pos += 1
        end
      end

      nil
    end

    def expand_single_template(content)
      parts = split_template_parts(content)
      return "" if parts.empty?

      template_name = parts[0].strip.downcase
      params = parse_template_params(parts[1..])

      case template_name
      # Date templates
      when "birth date", "birthdate"
        format_date(params, style: :mdy)
      when "birth date and age", "birthdate and age"
        format_date_with_age(params, style: :mdy, age_label: "age")
      when "death date", "deathdate"
        format_date(params, style: :mdy)
      when "death date and age", "deathdate and age"
        format_death_date_with_age(params)
      when "start date", "startdate"
        format_date(params, style: :mdy)
      when "end date", "enddate"
        format_date(params, style: :mdy)
      when "date"
        format_simple_date(params)

      # Age templates
      when "age"
        calculate_age(params)
      when "age in years"
        calculate_age_between_dates(params)
      when "age in days"
        calculate_days_between(params)
      when "age in years and days"
        calculate_age_years_and_days(params)
      when "time ago"
        format_time_ago(params)

      # Convert template
      when "convert", "cvt"
        expand_convert(params)

      # Common templates
      when "circa", "c."
        expand_circa(params)
      when "floruit", "fl."
        expand_floruit(params)
      when "reign", "r."
        expand_reign(params)
      when "marriage", "married"
        expand_marriage(params)
      when "played years"
        expand_year_range(params)

      else
        @preserve_unknown ? "{{#{content}}}" : ""
      end
    end

    def split_template_parts(content)
      parts = []
      current = +""
      depth = 0

      content.each_char do |c|
        if c == "{" || c == "["
          depth += 1
          current << c
        elsif c == "}" || c == "]"
          depth -= 1
          current << c
        elsif c == "|" && depth == 0
          parts << current
          current = +""
        else
          current << c
        end
      end

      parts << current unless current.empty?
      parts
    end

    def parse_template_params(parts)
      params = { positional: [] }

      parts.each do |part|
        if part.include?("=")
          key, value = part.split("=", 2)
          params[key.strip.downcase] = value&.strip
        else
          params[:positional] << part.strip
        end
      end

      params
    end

    # Date formatting methods

    def format_date(params, style: :mdy)
      pos = params[:positional]
      return "" if pos.empty?

      year = pos[0].to_i
      month = pos[1]&.to_i
      day = pos[2]&.to_i

      # Check for df=yes (day first)
      use_dmy = params["df"] == "yes" || params["df"] == "y"

      format_date_parts(year, month, day, use_dmy ? :dmy : style)
    end

    def format_date_parts(year, month, day, style)
      return year.to_s unless month && month > 0

      month_name = MONTH_NAMES[month - 1]
      return "#{month_name} #{year}" unless day && day > 0

      case style
      when :dmy
        "#{day} #{month_name} #{year}"
      else # :mdy
        "#{month_name} #{day}, #{year}"
      end
    end

    def format_simple_date(params)
      pos = params[:positional]
      return "" if pos.empty?

      year = pos[0].to_i
      month = pos[1]&.to_i
      day = pos[2]&.to_i

      format_date_parts(year, month, day, :mdy)
    end

    def format_date_with_age(params, style: :mdy, age_label: "age")
      pos = params[:positional]
      return "" if pos.empty?

      year = pos[0].to_i
      month = pos[1]&.to_i || 1
      day = pos[2]&.to_i || 1

      use_dmy = params["df"] == "yes" || params["df"] == "y"

      date_str = format_date_parts(year, month, day, use_dmy ? :dmy : style)
      age = calculate_age_from_parts(year, month, day, @reference_date)

      "#{date_str} (#{age_label} #{age})"
    end

    def format_death_date_with_age(params)
      pos = params[:positional]
      return "" if pos.length < 6

      death_year = pos[0].to_i
      death_month = pos[1].to_i
      death_day = pos[2].to_i
      birth_year = pos[3].to_i
      birth_month = pos[4].to_i
      birth_day = pos[5].to_i

      use_dmy = params["df"] == "yes" || params["df"] == "y"

      date_str = format_date_parts(death_year, death_month, death_day, use_dmy ? :dmy : :mdy)
      death_date = Time.new(death_year, death_month, death_day)
      age = calculate_age_from_parts(birth_year, birth_month, birth_day, death_date)

      "#{date_str} (aged #{age})"
    end

    # Age calculation methods

    def calculate_age(params)
      pos = params[:positional]
      return "" if pos.empty?

      year = pos[0].to_i
      month = pos[1]&.to_i || 1
      day = pos[2]&.to_i || 1

      calculate_age_from_parts(year, month, day, @reference_date).to_s
    end

    def calculate_age_from_parts(year, month, day, reference)
      birth = Time.new(year, month, day)
      age = reference.year - birth.year

      # Adjust if birthday hasn't occurred yet this year
      if reference.month < birth.month ||
         (reference.month == birth.month && reference.day < birth.day)
        age -= 1
      end

      age
    end

    def calculate_age_between_dates(params)
      pos = params[:positional]
      return "" if pos.length < 6

      birth_year = pos[0].to_i
      birth_month = pos[1].to_i
      birth_day = pos[2].to_i
      end_year = pos[3].to_i
      end_month = pos[4].to_i
      end_day = pos[5].to_i

      end_date = Time.new(end_year, end_month, end_day)
      calculate_age_from_parts(birth_year, birth_month, birth_day, end_date).to_s
    end

    def calculate_days_between(params)
      pos = params[:positional]
      return "" if pos.length < 6

      start_date = Time.new(pos[0].to_i, pos[1].to_i, pos[2].to_i)
      end_date = Time.new(pos[3].to_i, pos[4].to_i, pos[5].to_i)

      ((end_date - start_date) / 86400).to_i.to_s
    end

    def calculate_age_years_and_days(params)
      pos = params[:positional]
      return "" if pos.length < 6

      birth_year = pos[0].to_i
      birth_month = pos[1].to_i
      birth_day = pos[2].to_i
      end_year = pos[3].to_i
      end_month = pos[4].to_i
      end_day = pos[5].to_i

      birth_date = Time.new(birth_year, birth_month, birth_day)
      end_date = Time.new(end_year, end_month, end_day)

      years = calculate_age_from_parts(birth_year, birth_month, birth_day, end_date)

      # Calculate days since last birthday
      last_birthday = Time.new(end_year, birth_month, birth_day)
      last_birthday = Time.new(end_year - 1, birth_month, birth_day) if last_birthday > end_date
      days = ((end_date - last_birthday) / 86400).to_i

      "#{years} years, #{days} days"
    end

    def format_time_ago(params)
      pos = params[:positional]
      return "" if pos.empty?

      year = pos[0].to_i
      month = pos[1]&.to_i || 1
      day = pos[2]&.to_i || 1

      target = Time.new(year, month, day)
      diff_days = ((@reference_date - target) / 86400).to_i

      if diff_days < 30
        "#{diff_days} days ago"
      elsif diff_days < 365
        months = (diff_days / 30.0).round
        "#{months} months ago"
      else
        years = (diff_days / 365.0).round
        "#{years} years ago"
      end
    end

    # Convert template

    def expand_convert(params)
      pos = params[:positional]
      return "" if pos.empty?

      value = pos[0].to_f
      from_unit = pos[1]&.strip || ""
      to_unit = pos[2]&.strip || ""

      return "#{format_number(value)} #{from_unit}" if to_unit.empty?

      # Normalize units
      from_normalized = normalize_unit(from_unit)
      to_normalized = normalize_unit(to_unit)

      conversion = CONVERSIONS[[from_normalized, to_normalized]]

      if conversion.nil?
        "#{format_number(value)} #{UNIT_DISPLAY[from_normalized] || from_unit}"
      elsif conversion.is_a?(Symbol)
        # Special conversion (temperature)
        converted = send(conversion, value)
        from_display = UNIT_DISPLAY[from_normalized] || from_unit
        to_display = UNIT_DISPLAY[to_normalized] || to_unit
        "#{format_number(value)} #{from_display} (#{format_number(converted)} #{to_display})"
      else
        converted = value * conversion
        from_display = UNIT_DISPLAY[from_normalized] || from_unit
        to_display = UNIT_DISPLAY[to_normalized] || to_unit
        "#{format_number(value)} #{from_display} (#{format_number(converted)} #{to_display})"
      end
    end

    def normalize_unit(unit)
      # Remove common variations
      unit.gsub(/\s+/, "")
    end

    def format_number(value)
      # Format number, removing unnecessary decimals
      rounded = value.round(1)
      if rounded == rounded.to_i
        rounded.to_i.to_s
      else
        format("%.1f", rounded)
      end
    end

    def celsius_to_fahrenheit(c)
      (c * 9.0 / 5.0 + 32).round
    end

    def fahrenheit_to_celsius(f)
      ((f - 32) * 5.0 / 9.0).round
    end

    # Common template expansions

    def expand_circa(params)
      pos = params[:positional]
      return "" if pos.empty?

      if pos.length >= 2
        "c. #{pos[0]} – c. #{pos[1]}"
      else
        "c. #{pos[0]}"
      end
    end

    def expand_floruit(params)
      pos = params[:positional]
      return "" if pos.empty?

      if pos.length >= 2
        "fl. #{pos[0]}–#{pos[1]}"
      else
        "fl. #{pos[0]}"
      end
    end

    def expand_reign(params)
      pos = params[:positional]
      return "" if pos.length < 2

      "r. #{pos[0]}–#{pos[1]}"
    end

    def expand_marriage(params)
      pos = params[:positional]
      return "" if pos.empty?

      name = pos[0]
      start_year = pos[1]
      end_year = pos[2]

      reason = params["reason"]&.downcase

      if end_year && !end_year.empty?
        end_abbr = case reason
                   when "widowed", "wid" then "wid."
                   when "died", "d" then "d."
                   else "div."
                   end
        "#{name} (m. #{start_year}; #{end_abbr} #{end_year})"
      elsif start_year
        "#{name} (m. #{start_year})"
      else
        name.to_s
      end
    end

    def expand_year_range(params)
      pos = params[:positional]
      return "" if pos.length < 2

      "#{pos[0]}–#{pos[1]}"
    end
  end
end
