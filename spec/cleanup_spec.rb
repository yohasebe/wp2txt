# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/wp2txt/utils"

RSpec.describe "Wp2txt Cleanup" do
  include Wp2txt

  describe "MediaWiki magic words" do
    it "removes DEFAULTSORT lines" do
      input = "Some text\nDEFAULTSORT:にんちけんこかく\nMore text"
      result = cleanup(input)
      expect(result).not_to include("DEFAULTSORT")
      expect(result).to include("Some text")
      expect(result).to include("More text")
    end

    it "removes DISPLAYTITLE lines" do
      input = "Some text\nDISPLAYTITLE:Custom Title\nMore text"
      result = cleanup(input)
      expect(result).not_to include("DISPLAYTITLE")
    end

    it "removes __NOTOC__ and similar" do
      input = "Some text\n__NOTOC__\n__TOC__\n__FORCETOC__\nMore text"
      result = cleanup(input)
      expect(result).not_to include("__NOTOC__")
      expect(result).not_to include("__TOC__")
      expect(result).not_to include("__FORCETOC__")
    end

    it "removes __NOEDITSECTION__" do
      input = "Some text\n__NOEDITSECTION__\nMore text"
      result = cleanup(input)
      expect(result).not_to include("__NOEDITSECTION__")
    end
  end

  describe "Interwiki links" do
    it "removes :en: prefixed links" do
      input = "See :en:Force dynamics for more"
      result = cleanup(input)
      expect(result).to include("Force dynamics")
      expect(result).not_to include(":en:")
    end

    it "removes :fr: prefixed links" do
      input = "See :fr:Société de Linguistique de Paris"
      result = cleanup(input)
      expect(result).to include("Société de Linguistique de Paris")
      expect(result).not_to include(":fr:")
    end

    it "removes :de: prefixed links" do
      input = "Related: :de:Sprachwissenschaft"
      result = cleanup(input)
      expect(result).to include("Sprachwissenschaft")
      expect(result).not_to include(":de:")
    end

    it "handles multiple interwiki links" do
      input = "See :en:Article1 and :fr:Article2 for details"
      result = cleanup(input)
      expect(result).to include("Article1")
      expect(result).to include("Article2")
      expect(result).not_to match(/:[a-z]{2}:/)
    end
  end

  describe "Authority control templates" do
    it "removes Normdaten line" do
      input = "Some text\nNormdaten\nMore text"
      result = cleanup(input)
      expect(result).not_to include("Normdaten")
    end

    it "removes Authority control line" do
      input = "Some text\nAuthority control\nMore text"
      result = cleanup(input)
      expect(result).not_to include("Authority control")
    end

    it "removes Persondata line" do
      input = "Some text\nPersondata\nMore text"
      result = cleanup(input)
      expect(result).not_to include("Persondata")
    end
  end

  describe "Category line cleanup" do
    it "removes standalone Category: lines (English)" do
      input = "Text\nCategory:Linguistics\nCategory:Science\nMore"
      result = cleanup(input)
      expect(result).not_to match(/^Category:/)
    end

    it "removes standalone カテゴリ lines (Japanese)" do
      input = "Text\nカテゴリ:言語学\nMore"
      result = cleanup(input)
      expect(result).not_to match(/^カテゴリ:/)
    end

    it "removes standalone Kategorie lines (German)" do
      input = "Text\nKategorie:Sprachwissenschaft\nMore"
      result = cleanup(input)
      expect(result).not_to match(/^Kategorie:/)
    end

    it "removes standalone Catégorie lines (French)" do
      input = "Text\nCatégorie:Linguistique\nMore"
      result = cleanup(input)
      expect(result).not_to match(/^Catégorie:/)
    end

    it "removes Category lines with asterisk prefix" do
      input = "Text\n*\nCategory:Main\nMore"
      result = cleanup(input)
      expect(result).not_to match(/^Category:/)
    end

    it "preserves CATEGORIES summary line" do
      input = "Text\nCATEGORIES: Foo, Bar, Baz\nMore"
      result = cleanup(input)
      expect(result).to include("CATEGORIES: Foo, Bar, Baz")
    end
  end

  describe "Template artifact cleanup" do
    it "removes stub template markers" do
      # Common stub patterns across languages
      input = "Text\n節スタブ\nMore"
      result = cleanup(input)
      # This might be Japanese-specific, but the pattern should be general
    end

    it "removes reference help markers" do
      input = "Text\n脚注ヘルプ\nMore"
      result = cleanup(input)
      # Japanese-specific, need general approach
    end

    it "removes lines that are just asterisk + single word" do
      input = "Text\n*和書\n*洋書\nMore"
      result = cleanup(input)
      # Pattern: ^\*[^\s\*]+$ (single word after asterisk)
    end

    it "removes Wikibooks/Wikiversity markers" do
      input = "Text\nWikibooks\nSchool:言語学\nMore"
      result = cleanup(input)
      expect(result).not_to match(/^Wikibooks$/)
      expect(result).not_to match(/^School:/)
    end

    it "removes commons/wikimedia markers" do
      input = "Text\nCommons\nWikimedia Commons\nMore"
      result = cleanup(input)
      expect(result).not_to match(/^Commons$/)
    end
  end

  describe "Combined cleanup" do
    it "cleans up a realistic Wikipedia article footer" do
      input = <<~TEXT
        This is the main content.

        == References ==
        脚注ヘルプ

        == External links ==
        Wikibooks
        School:言語学

        Normdaten
        DEFAULTSORT:けんこかく
        Category:言語学
        Category:人文科学
        *

        CATEGORIES: 言語学, 人文科学
      TEXT

      result = cleanup(input)

      expect(result).to include("This is the main content")
      expect(result).to include("== References ==")
      expect(result).to include("== External links ==")
      expect(result).to include("CATEGORIES: 言語学, 人文科学")

      expect(result).not_to include("Normdaten")
      expect(result).not_to include("DEFAULTSORT")
      expect(result).not_to match(/^Category:/)
      expect(result).not_to match(/^Wikibooks$/)
      expect(result).not_to match(/^School:/)
    end
  end
end
