# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MediaWiki Data" do
  describe "extension_tags in mediawiki_aliases.json" do
    before(:all) do
      data_path = File.join(__dir__, "..", "lib", "wp2txt", "data", "mediawiki_aliases.json")
      @mediawiki_data = JSON.parse(File.read(data_path))
    end

    it "contains extension_tags array" do
      expect(@mediawiki_data["extension_tags"]).to be_an(Array)
    end

    it "contains common extension tags" do
      tags = @mediawiki_data["extension_tags"]
      expect(tags).to include("gallery")
      expect(tags).to include("timeline")
      expect(tags).to include("imagemap")
      expect(tags).to include("math")
      expect(tags).to include("ref")
      expect(tags).to include("syntaxhighlight")
    end

    it "contains German-specific tag" do
      tags = @mediawiki_data["extension_tags"]
      expect(tags).to include("abschnitt")  # German for "section"
    end
  end
end

RSpec.describe "Template Data" do
  let(:data_path) { File.join(__dir__, "..", "lib", "wp2txt", "data", "template_aliases.json") }

  describe "template_aliases.json" do
    before(:all) do
      @data = if File.exist?(File.join(__dir__, "..", "lib", "wp2txt", "data", "template_aliases.json"))
        JSON.parse(File.read(File.join(__dir__, "..", "lib", "wp2txt", "data", "template_aliases.json")))
      else
        nil
      end
    end

    it "exists" do
      expect(File.exist?(data_path)).to be true
    end

    it "has valid JSON structure" do
      expect(@data).to be_a(Hash)
    end

    it "has meta information" do
      expect(@data["meta"]).to be_a(Hash)
      expect(@data["meta"]["generated_at"]).to be_a(String)
    end

    describe "remove_templates category" do
      it "exists and is an array" do
        expect(@data["remove_templates"]).to be_an(Array)
      end

      it "contains known navigation templates" do
        templates = @data["remove_templates"].map(&:downcase)
        # These should be removed in all languages
        expect(templates).to include("reflist")
        expect(templates).to include("refbegin")
        expect(templates).to include("refend")
        expect(templates).to include("notelist")
      end

      it "contains hatnote templates" do
        templates = @data["remove_templates"].map(&:downcase)
        expect(templates).to include("main")
        expect(templates).to include("see also")
        expect(templates).to include("further")
        expect(templates).to include("about")
      end
    end

    describe "authority_control category" do
      it "exists and is an array" do
        expect(@data["authority_control"]).to be_an(Array)
      end

      it "contains English authority control templates" do
        templates = @data["authority_control"].map(&:downcase)
        expect(templates).to include("authority control")
      end

      it "contains German Normdaten template" do
        templates = @data["authority_control"].map(&:downcase)
        expect(templates).to include("normdaten")
      end

      it "contains identifier templates" do
        templates = @data["authority_control"].map(&:downcase)
        %w[viaf lccn gnd isni orcid].each do |id|
          expect(templates).to include(id)
        end
      end
    end

    describe "cleanup_remnants category" do
      it "exists and is an array" do
        expect(@data["cleanup_remnants"]).to be_an(Array)
      end

      it "contains layout templates" do
        templates = @data["cleanup_remnants"].map(&:downcase)
        expect(templates).to include("clear")
        expect(templates).to include("clearleft")
        expect(templates).to include("clearright")
      end
    end

    describe "citation_templates category" do
      it "exists and is an array" do
        expect(@data["citation_templates"]).to be_an(Array)
      end

      it "contains cite templates in multiple languages" do
        templates = @data["citation_templates"].map(&:downcase)
        # English
        expect(templates).to include("cite web")
        expect(templates).to include("cite book")
        expect(templates).to include("citation")
        # Japanese
        expect(templates).to include("cite web")  # Same in Japanese Wikipedia
      end
    end

    describe "ruby_text_templates category" do
      it "exists and is an array" do
        expect(@data["ruby_text_templates"]).to be_an(Array)
      end

      it "contains Japanese ruby template" do
        templates = @data["ruby_text_templates"]
        expect(templates).to include("読み仮名")
      end

      it "contains English ruby templates" do
        templates = @data["ruby_text_templates"].map(&:downcase)
        expect(templates).to include("ruby")
        expect(templates).to include("ruby-ja")
      end
    end

    describe "interwiki_link_templates category" do
      it "exists and is an array" do
        expect(@data["interwiki_link_templates"]).to be_an(Array)
      end

      it "contains Japanese 仮リンク template" do
        templates = @data["interwiki_link_templates"]
        expect(templates).to include("仮リンク")
      end

      it "contains interlanguage link templates" do
        templates = @data["interwiki_link_templates"].map(&:downcase)
        expect(templates).to include("ill")  # Interlanguage link
        expect(templates).to include("interlanguage link")
      end
    end

    describe "mixed_script_templates category" do
      it "exists and is an array" do
        expect(@data["mixed_script_templates"]).to be_an(Array)
      end

      it "contains nihongo template" do
        templates = @data["mixed_script_templates"].map(&:downcase)
        expect(templates).to include("nihongo")
      end

      it "contains transliteration templates" do
        templates = @data["mixed_script_templates"].map(&:downcase)
        expect(templates).to include("transl")
      end
    end

    describe "formatting_templates category" do
      it "exists and is an array" do
        expect(@data["formatting_templates"]).to be_an(Array)
      end

      it "contains size templates" do
        templates = @data["formatting_templates"].map(&:downcase)
        expect(templates).to include("small")
        expect(templates).to include("smaller")
        expect(templates).to include("large")
        expect(templates).to include("larger")
      end

      it "contains spacing templates" do
        templates = @data["formatting_templates"].map(&:downcase)
        expect(templates).to include("nbsp")
        expect(templates).to include("nowrap")
      end
    end

    describe "flag_templates category" do
      it "exists and is an array" do
        expect(@data["flag_templates"]).to be_an(Array)
      end

      it "contains flag template variants" do
        templates = @data["flag_templates"].map(&:downcase)
        expect(templates).to include("flag")
        expect(templates).to include("flagicon")
        expect(templates).to include("flagcountry")
      end
    end

    describe "portal_templates category" do
      it "exists and is an array" do
        expect(@data["portal_templates"]).to be_an(Array)
      end

      it "contains portal templates in multiple languages" do
        templates = @data["portal_templates"].map(&:downcase)
        expect(templates).to include("portal")
        # Japanese
        expect(@data["portal_templates"]).to include("ウィキポータルリンク")
      end
    end

    describe "sister_project_templates category" do
      it "exists and is an array" do
        expect(@data["sister_project_templates"]).to be_an(Array)
      end

      it "contains commons templates" do
        templates = @data["sister_project_templates"].map(&:downcase)
        expect(templates).to include("commons")
        expect(templates).to include("commons category")
      end

      it "contains wiktionary templates" do
        templates = @data["sister_project_templates"].map(&:downcase)
        expect(templates).to include("wiktionary")
      end
    end
  end
end
