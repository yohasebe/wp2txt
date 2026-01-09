# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Template Processing (Data-Driven)" do
  include Wp2txt

  # Helper to extract template name from {{...}} for testing regex
  def template_content(str)
    str.gsub(/^\{\{/, "").gsub(/\}\}$/, "")
  end

  describe "REMOVE_TEMPLATES_REGEX" do
    it "is loaded from template_aliases.json" do
      # Verify the constant exists and is a Regexp
      expect(Wp2txt::REMOVE_TEMPLATES_REGEX).to be_a(Regexp)
    end

    it "matches English navigation templates" do
      %w[sfn efn refn reflist notelist main portal].each do |template|
        content = "#{template}|content"
        expect(content).to match(Wp2txt::REMOVE_TEMPLATES_REGEX), "Expected '#{template}' to match"
      end
    end

    it "matches hatnote templates" do
      %w[about redirect distinguish further details].each do |template|
        content = "#{template}|content"
        expect(content).to match(Wp2txt::REMOVE_TEMPLATES_REGEX), "Expected '#{template}' to match"
      end
    end

    it "matches Japanese navigation templates" do
      expect("脚注ヘルプ").to match(Wp2txt::REMOVE_TEMPLATES_REGEX)
      expect("関連項目|記事").to match(Wp2txt::REMOVE_TEMPLATES_REGEX)
    end

    it "matches German navigation templates" do
      expect("Hauptartikel|Artikel").to match(Wp2txt::REMOVE_TEMPLATES_REGEX)
      expect("Siehe auch|Artikel").to match(Wp2txt::REMOVE_TEMPLATES_REGEX)
    end

    it "matches French navigation templates" do
      expect("Article principal|Article").to match(Wp2txt::REMOVE_TEMPLATES_REGEX)
      expect("Voir aussi|Article").to match(Wp2txt::REMOVE_TEMPLATES_REGEX)
    end

    it "does not match citation templates" do
      expect("cite web|url=...").not_to match(Wp2txt::REMOVE_TEMPLATES_REGEX)
      expect("cite book|title=...").not_to match(Wp2txt::REMOVE_TEMPLATES_REGEX)
    end
  end

  describe "AUTHORITY_CONTROL_REGEX" do
    it "is loaded from template_aliases.json" do
      expect(Wp2txt::AUTHORITY_CONTROL_REGEX).to be_a(Regexp)
    end

    it "matches English authority control" do
      expect("Authority control").to match(Wp2txt::AUTHORITY_CONTROL_REGEX)
    end

    it "matches German Normdaten" do
      expect("Normdaten").to match(Wp2txt::AUTHORITY_CONTROL_REGEX)
    end

    it "matches identifier templates" do
      %w[VIAF LCCN GND ISNI ORCID].each do |id|
        expect(id).to match(Wp2txt::AUTHORITY_CONTROL_REGEX)
      end
    end
  end

  describe "CLEANUP_REMNANTS_REGEX" do
    it "is loaded from template_aliases.json" do
      expect(Wp2txt::CLEANUP_REMNANTS_REGEX).to be_a(Regexp)
    end

    it "matches layout templates" do
      %w[Clear Clearleft Clearright].each do |template|
        expect(template).to match(Wp2txt::CLEANUP_REMNANTS_REGEX)
      end
    end

    it "matches notelist variants" do
      expect("notelist").to match(Wp2txt::CLEANUP_REMNANTS_REGEX)
      expect("notelist2").to match(Wp2txt::CLEANUP_REMNANTS_REGEX)
    end
  end

  describe "correct_inline_template" do
    # Ruby text templates (読み仮名 equivalent)
    describe "ruby text templates" do
      it "handles Japanese 読み仮名 template" do
        result = correct_inline_template("{{読み仮名|漢字|かんじ}}")
        expect(result).to eq("漢字（かんじ）")
      end

      it "handles English ruby template" do
        result = correct_inline_template("{{ruby|漢字|かんじ}}")
        expect(result).to include("漢字")
      end
    end

    # Interwiki link templates (仮リンク equivalent)
    describe "interwiki link templates" do
      it "handles Japanese 仮リンク template" do
        result = correct_inline_template("{{仮リンク|表示名|en|English Article}}")
        expect(result).to eq("表示名")
      end

      it "handles English ill template" do
        result = correct_inline_template("{{ill|Display|ja|日本語記事}}")
        expect(result).to eq("Display")
      end

      it "handles interlanguage link template" do
        result = correct_inline_template("{{interlanguage link|Display|de|Deutscher Artikel}}")
        expect(result).to eq("Display")
      end
    end

    # Mixed script templates (nihongo equivalent)
    describe "mixed script templates" do
      it "handles nihongo template with all parts" do
        result = correct_inline_template("{{nihongo|Tokyo|東京|Tōkyō}}")
        expect(result).to eq("Tokyo (東京, Tōkyō)")
      end

      it "handles nihongo template with only kanji" do
        result = correct_inline_template("{{nihongo|Tokyo|東京}}")
        expect(result).to eq("Tokyo (東京)")
      end

      it "handles transl template" do
        result = correct_inline_template("{{transl|ja|tōkyō}}")
        expect(result).to eq("tōkyō")
      end
    end

    # Convert templates
    describe "convert templates" do
      it "handles convert template" do
        result = correct_inline_template("{{convert|100|km}}")
        expect(result).to eq("100 km")
      end

      it "handles Japanese 単位変換 template" do
        result = correct_inline_template("{{単位変換|100|km}}")
        expect(result).to eq("100 km")
      end
    end

    # Flag templates
    describe "flag templates" do
      it "removes flag templates" do
        result = correct_inline_template("{{flag|Japan}}")
        expect(result).to eq("")
      end

      it "removes flagicon templates" do
        result = correct_inline_template("{{flagicon|USA}}")
        expect(result).to eq("")
      end

      it "removes country code templates" do
        result = correct_inline_template("{{JPN}}")
        expect(result).to eq("")
      end
    end

    # Formatting templates
    describe "formatting templates" do
      it "extracts content from small template" do
        result = correct_inline_template("{{small|text}}")
        expect(result).to eq("text")
      end

      it "extracts content from nowrap template" do
        result = correct_inline_template("{{nowrap|text here}}")
        expect(result).to eq("text here")
      end

      it "handles nbsp template" do
        result = correct_inline_template("before{{nbsp}}after")
        expect(result).to eq("before after")
      end
    end
  end

  describe "cleanup" do
    it "removes authority control remnants" do
      text = "Article content\n\nAuthority control\n\n"
      result = cleanup(text)
      expect(result).not_to include("Authority control")
    end

    it "removes Normdaten remnants" do
      text = "Article content\n\nNormdaten\n\n"
      result = cleanup(text)
      expect(result).not_to include("Normdaten")
    end

    it "removes cleanup remnants like Clearleft" do
      text = "Content\n\nClearleft\n\nMore content"
      result = cleanup(text)
      expect(result).not_to include("Clearleft")
    end

    it "removes sister project markers" do
      text = "Content\n\nCommons:\n\nWiktionary:\n\n"
      result = cleanup(text)
      expect(result).not_to include("Commons:")
      expect(result).not_to include("Wiktionary:")
    end
  end
end
