# frozen_string_literal: true

require "spec_helper"

RSpec.describe Wp2txt::TemplateExpander do
  let(:expander) { described_class.new }
  # Fixed reference date for age calculations
  let(:reference_date) { Time.new(2024, 6, 15) }
  let(:expander_with_date) { described_class.new(reference_date: reference_date) }

  describe "date templates" do
    describe "{{birth date}}" do
      it "expands {{birth date|1990|5|15}} to formatted date" do
        expect(expander.expand("{{birth date|1990|5|15}}")).to eq("May 15, 1990")
      end

      it "expands {{Birth date|1990|5|15}} (case-insensitive)" do
        expect(expander.expand("{{Birth date|1990|5|15}}")).to eq("May 15, 1990")
      end

      it "handles single-digit day" do
        expect(expander.expand("{{birth date|1990|5|5}}")).to eq("May 5, 1990")
      end

      it "handles different months" do
        expect(expander.expand("{{birth date|2000|12|25}}")).to eq("December 25, 2000")
      end

      it "handles df=yes parameter (day first)" do
        expect(expander.expand("{{birth date|1990|5|15|df=yes}}")).to eq("15 May 1990")
      end

      it "handles mf=yes parameter (month first, default)" do
        expect(expander.expand("{{birth date|1990|5|15|mf=yes}}")).to eq("May 15, 1990")
      end
    end

    describe "{{birth date and age}}" do
      it "expands with calculated age" do
        result = expander_with_date.expand("{{birth date and age|1990|5|15}}")
        expect(result).to eq("May 15, 1990 (age 34)")
      end

      it "calculates age correctly when birthday hasn't occurred yet" do
        result = expander_with_date.expand("{{birth date and age|1990|12|25}}")
        expect(result).to eq("December 25, 1990 (age 33)")
      end

      it "handles df=yes parameter" do
        result = expander_with_date.expand("{{birth date and age|1990|5|15|df=yes}}")
        expect(result).to eq("15 May 1990 (age 34)")
      end
    end

    describe "{{death date}}" do
      it "expands {{death date|2020|3|1}} to formatted date" do
        expect(expander.expand("{{death date|2020|3|1}}")).to eq("March 1, 2020")
      end

      it "handles df=yes parameter" do
        expect(expander.expand("{{death date|2020|3|1|df=yes}}")).to eq("1 March 2020")
      end
    end

    describe "{{death date and age}}" do
      it "expands with age at death" do
        result = expander.expand("{{death date and age|2020|3|1|1950|6|15}}")
        expect(result).to eq("March 1, 2020 (aged 69)")
      end

      it "handles df=yes parameter" do
        result = expander.expand("{{death date and age|2020|3|1|1950|6|15|df=yes}}")
        expect(result).to eq("1 March 2020 (aged 69)")
      end
    end

    describe "{{start date}}" do
      it "expands to formatted date" do
        expect(expander.expand("{{start date|2024|1|1}}")).to eq("January 1, 2024")
      end

      it "handles df=yes parameter" do
        expect(expander.expand("{{start date|2024|1|1|df=yes}}")).to eq("1 January 2024")
      end
    end

    describe "{{end date}}" do
      it "expands to formatted date" do
        expect(expander.expand("{{end date|2024|12|31}}")).to eq("December 31, 2024")
      end
    end

    describe "{{date}}" do
      it "expands simple date" do
        expect(expander.expand("{{date|2024|6|15}}")).to eq("June 15, 2024")
      end

      it "handles year and month only" do
        expect(expander.expand("{{date|2024|6}}")).to eq("June 2024")
      end

      it "handles year only" do
        expect(expander.expand("{{date|2024}}")).to eq("2024")
      end
    end
  end

  describe "age templates" do
    describe "{{age}}" do
      it "calculates age from birth date" do
        result = expander_with_date.expand("{{age|1990|5|15}}")
        expect(result).to eq("34")
      end

      it "returns correct age when birthday hasn't occurred" do
        result = expander_with_date.expand("{{age|1990|12|25}}")
        expect(result).to eq("33")
      end
    end

    describe "{{age in years}}" do
      it "calculates age between two dates" do
        result = expander.expand("{{age in years|1950|6|15|2020|3|1}}")
        expect(result).to eq("69")
      end
    end

    describe "{{age in days}}" do
      it "calculates days between dates" do
        result = expander.expand("{{age in days|2024|1|1|2024|1|10}}")
        expect(result).to eq("9")
      end
    end
  end

  describe "convert templates" do
    describe "length conversions" do
      it "converts km to mi" do
        result = expander.expand("{{convert|100|km|mi}}")
        expect(result).to match(/100 km \(6[0-9](\.[0-9])? mi\)/)
      end

      it "converts mi to km" do
        result = expander.expand("{{convert|100|mi|km}}")
        expect(result).to match(/100 mi \(16[0-9](\.[0-9])? km\)/)
      end

      it "converts m to ft" do
        result = expander.expand("{{convert|100|m|ft}}")
        expect(result).to match(/100 m \(32[0-9](\.[0-9])? ft\)/)
      end

      it "converts ft to m" do
        result = expander.expand("{{convert|100|ft|m}}")
        expect(result).to match(/100 ft \(30(\.[0-9])? m\)/)
      end

      it "converts cm to in" do
        result = expander.expand("{{convert|100|cm|in}}")
        expect(result).to match(/100 cm \(39(\.[0-9])? in\)/)
      end

      it "converts in to cm" do
        result = expander.expand("{{convert|10|in|cm}}")
        expect(result).to match(/10 in \(25(\.[0-9])? cm\)/)
      end
    end

    describe "weight conversions" do
      it "converts kg to lb" do
        result = expander.expand("{{convert|100|kg|lb}}")
        expect(result).to match(/100 kg \(22[0-9](\.[0-9])? lb\)/)
      end

      it "converts lb to kg" do
        result = expander.expand("{{convert|100|lb|kg}}")
        expect(result).to match(/100 lb \(4[0-9](\.[0-9])? kg\)/)
      end

      it "converts g to oz" do
        result = expander.expand("{{convert|100|g|oz}}")
        expect(result).to match(/100 g \(3\.[0-9] oz\)/)
      end
    end

    describe "temperature conversions" do
      it "converts °C to °F" do
        expect(expander.expand("{{convert|0|°C|°F}}")).to eq("0 °C (32 °F)")
      end

      it "converts C to F (without degree symbol)" do
        expect(expander.expand("{{convert|100|C|F}}")).to eq("100 °C (212 °F)")
      end

      it "converts °F to °C" do
        expect(expander.expand("{{convert|32|°F|°C}}")).to eq("32 °F (0 °C)")
      end

      it "converts F to C (without degree symbol)" do
        expect(expander.expand("{{convert|212|F|C}}")).to eq("212 °F (100 °C)")
      end
    end

    describe "area conversions" do
      it "converts km2 to sqmi" do
        result = expander.expand("{{convert|100|km2|sqmi}}")
        expect(result).to match(/100 km² \(3[0-9](\.[0-9])? sq mi\)/)
      end

      it "converts sqmi to km2" do
        result = expander.expand("{{convert|100|sqmi|km2}}")
        expect(result).to match(/100 sq mi \(25[0-9](\.[0-9])? km²\)/)
      end

      it "converts ha to acre" do
        result = expander.expand("{{convert|100|ha|acre}}")
        expect(result).to match(/100 ha \(24[0-9](\.[0-9])? acres\)/)
      end
    end

    describe "speed conversions" do
      it "converts km/h to mph" do
        result = expander.expand("{{convert|100|km/h|mph}}")
        expect(result).to match(/100 km\/h \(6[0-9](\.[0-9])? mph\)/)
      end

      it "converts mph to km/h" do
        result = expander.expand("{{convert|60|mph|km/h}}")
        expect(result).to match(/60 mph \(9[0-9](\.[0-9])? km\/h\)/)
      end
    end

    describe "edge cases" do
      it "handles decimal values" do
        result = expander.expand("{{convert|3.5|km|mi}}")
        expect(result).to match(/3\.5 km \(2\.[0-9] mi\)/)
      end

      it "handles unknown units gracefully" do
        expect(expander.expand("{{convert|100|foo|bar}}")).to eq("100 foo")
      end

      it "handles abbr=on parameter" do
        result = expander.expand("{{convert|100|km|mi|abbr=on}}")
        expect(result).to match(/100 km \(6[0-9](\.[0-9])? mi\)/)
      end
    end
  end

  describe "common templates" do
    describe "{{circa}}" do
      it "expands to c. prefix" do
        expect(expander.expand("{{circa|1500}}")).to eq("c. 1500")
      end

      it "handles range" do
        expect(expander.expand("{{circa|1500|1550}}")).to eq("c. 1500 – c. 1550")
      end
    end

    describe "{{floruit}}" do
      it "expands single year" do
        expect(expander.expand("{{floruit|1500}}")).to eq("fl. 1500")
      end

      it "expands year range" do
        expect(expander.expand("{{floruit|1500|1550}}")).to eq("fl. 1500–1550")
      end
    end

    describe "{{reign}}" do
      it "expands reign years" do
        expect(expander.expand("{{reign|1500|1550}}")).to eq("r. 1500–1550")
      end
    end

    describe "{{marriage}}" do
      it "expands simple marriage" do
        expect(expander.expand("{{marriage|Jane Doe|1990}}")).to eq("Jane Doe (m. 1990)")
      end

      it "expands marriage with end" do
        expect(expander.expand("{{marriage|Jane Doe|1990|2020}}")).to eq("Jane Doe (m. 1990; div. 2020)")
      end

      it "handles widowed end reason" do
        expect(expander.expand("{{marriage|Jane Doe|1990|2020|reason=widowed}}")).to eq("Jane Doe (m. 1990; wid. 2020)")
      end

      it "handles died end reason" do
        expect(expander.expand("{{marriage|Jane Doe|1990|2020|reason=died}}")).to eq("Jane Doe (m. 1990; d. 2020)")
      end
    end

    describe "{{played years}}" do
      it "expands playing career span" do
        expect(expander.expand("{{played years|2000|2020}}")).to eq("2000–2020")
      end
    end

    describe "{{age in years and days}}" do
      it "formats age with years and days" do
        result = expander.expand("{{age in years and days|1990|1|1|2024|6|15}}")
        expect(result).to match(/34 years, \d+ days/)
      end
    end

    describe "{{time ago}}" do
      it "formats time since date" do
        result = expander_with_date.expand("{{time ago|2024|1|1}}")
        expect(result).to match(/\d+ months ago/)
      end
    end
  end

  describe "formatting preservation" do
    it "preserves text around templates" do
      result = expander.expand("Born on {{birth date|1990|5|15}} in Tokyo")
      expect(result).to eq("Born on May 15, 1990 in Tokyo")
    end

    it "handles multiple templates in one string" do
      result = expander.expand("{{birth date|1990|5|15}} – {{death date|2020|3|1}}")
      expect(result).to eq("May 15, 1990 – March 1, 2020")
    end

    it "handles nested templates" do
      # This tests that inner templates are expanded first
      result = expander.expand("Born {{circa|1500}}")
      expect(result).to eq("Born c. 1500")
    end
  end

  describe "unknown templates" do
    it "returns empty for unknown templates" do
      expect(expander.expand("{{unknown template|foo|bar}}")).to eq("")
    end

    it "can be configured to preserve unknown templates" do
      exp = described_class.new(preserve_unknown: true)
      expect(exp.expand("{{unknown|foo}}")).to eq("{{unknown|foo}}")
    end
  end

  describe "coordinate templates" do
    describe "{{coord}}" do
      it "expands decimal coordinates" do
        result = expander.expand("{{coord|40.7128|N|74.0060|W}}")
        expect(result).to match(/40\.7128°\s*N.*74\.0060°\s*W/i)
      end

      it "expands DMS coordinates" do
        result = expander.expand("{{coord|40|42|46|N|74|0|22|W}}")
        expect(result).to match(/40°42['′]46["″]?\s*N.*74°0['′]22["″]?\s*W/i)
      end

      it "expands coordinates with display parameter" do
        result = expander.expand("{{coord|51.5074|N|0.1278|W|display=title}}")
        expect(result).to include("51.5074")
      end

      it "handles simple lat/lon format" do
        result = expander.expand("{{coord|35.6762|139.6503}}")
        expect(result).to include("35.6762")
        expect(result).to include("139.6503")
      end
    end
  end

  describe "language templates" do
    describe "{{lang}}" do
      it "expands basic lang template" do
        expect(expander.expand("{{lang|fr|Bonjour}}")).to eq("Bonjour")
      end

      it "expands with literal translation" do
        result = expander.expand("{{lang|la|Carpe diem|lit=seize the day}}")
        expect(result).to include("Carpe diem")
        expect(result).to include("seize the day")
      end
    end

    describe "{{lang-xx}}" do
      it "expands lang-fr template" do
        result = expander.expand("{{lang-fr|Bonjour}}")
        expect(result).to match(/French.*Bonjour/i)
      end

      it "expands lang-de template" do
        result = expander.expand("{{lang-de|Guten Tag}}")
        expect(result).to match(/German.*Guten Tag/i)
      end

      it "expands lang-ja template" do
        result = expander.expand("{{lang-ja|こんにちは}}")
        expect(result).to match(/Japanese.*こんにちは/i)
      end

      it "expands lang-la template with literal" do
        result = expander.expand("{{lang-la|Veni, vidi, vici|lit=I came, I saw, I conquered}}")
        expect(result).to include("Latin")
        expect(result).to include("Veni, vidi, vici")
        expect(result).to include("I came, I saw, I conquered")
      end
    end

    describe "{{transl}}" do
      it "expands transliteration template" do
        result = expander.expand("{{transl|ru|Moskva}}")
        expect(result).to eq("Moskva")
      end
    end

    describe "{{nihongo}}" do
      it "expands nihongo template" do
        result = expander.expand("{{nihongo|Tokyo|東京|Tōkyō}}")
        expect(result).to include("Tokyo")
        expect(result).to include("東京")
        expect(result).to include("Tōkyō")
      end

      it "handles nihongo without romaji" do
        result = expander.expand("{{nihongo|Tokyo|東京}}")
        expect(result).to include("Tokyo")
        expect(result).to include("東京")
      end
    end
  end

  describe "formatting templates" do
    describe "{{nowrap}}" do
      it "preserves text" do
        expect(expander.expand("{{nowrap|100 km}}")).to eq("100 km")
      end
    end

    describe "{{small}}" do
      it "preserves text" do
        expect(expander.expand("{{small|tiny text}}")).to eq("tiny text")
      end
    end

    describe "{{em}}" do
      it "preserves text (emphasis)" do
        expect(expander.expand("{{em|important}}")).to eq("important")
      end
    end

    describe "{{abbr}}" do
      it "returns abbreviation" do
        expect(expander.expand("{{abbr|HTML|Hypertext Markup Language}}")).to eq("HTML")
      end
    end
  end

  describe "integration with format_wiki" do
    include Wp2txt

    it "expands templates during format_wiki processing" do
      input = "He was born on {{birth date|1990|5|15}}."
      result = format_wiki(input, title: "Test", expand_templates: true)
      expect(result).to include("May 15, 1990")
    end

    it "expands convert templates" do
      input = "The mountain is {{convert|8848|m|ft}} tall."
      result = format_wiki(input, title: "Test", expand_templates: true)
      expect(result).to include("8848 m")
      expect(result).to include("ft")
    end
  end
end
