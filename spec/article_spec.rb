# frozen_string_literal: true

require_relative "spec_helper"
require_relative "fixtures/samples"

RSpec.describe Wp2txt::Article do
  # Use let blocks for lazy evaluation to avoid triggering bugs at load time
  let(:english_article) { Wp2txt::TestSamples::ENGLISH_ARTICLE }
  let(:japanese_article) { Wp2txt::TestSamples::JAPANESE_ARTICLE }
  let(:german_article) { Wp2txt::TestSamples::GERMAN_ARTICLE }
  let(:french_article) { Wp2txt::TestSamples::FRENCH_ARTICLE }
  let(:chinese_article) { Wp2txt::TestSamples::CHINESE_ARTICLE }
  let(:russian_article) { Wp2txt::TestSamples::RUSSIAN_ARTICLE }
  let(:korean_article) { Wp2txt::TestSamples::KOREAN_ARTICLE }
  let(:arabic_article) { Wp2txt::TestSamples::ARABIC_ARTICLE }
  let(:emoji_content) { Wp2txt::TestSamples::EMOJI_CONTENT }
  let(:deeply_nested) { Wp2txt::TestSamples::DEEPLY_NESTED }
  let(:malformed_markup) { Wp2txt::TestSamples::MALFORMED_MARKUP }
  let(:nested_templates) { Wp2txt::TestSamples::NESTED_TEMPLATES }
  let(:table_content) { Wp2txt::TestSamples::TABLE_CONTENT }
  let(:reference_content) { Wp2txt::TestSamples::REFERENCE_CONTENT }
  let(:multiline_link) { Wp2txt::TestSamples::MULTILINE_LINK }

  describe "#parse" do
    it "classifies headings correctly" do
      article = Wp2txt::Article.new("== Heading ==\nParagraph text")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_heading)
      expect(types).to include(:mw_paragraph)
    end

    it "classifies unordered lists" do
      article = Wp2txt::Article.new("* Item 1\n* Item 2\n* Item 3")
      types = article.elements.map(&:first)
      expect(types.count(:mw_unordered)).to eq 3
    end

    it "classifies ordered lists" do
      article = Wp2txt::Article.new("# First\n# Second\n# Third")
      types = article.elements.map(&:first)
      expect(types.count(:mw_ordered)).to eq 3
    end

    it "classifies definition lists" do
      article = Wp2txt::Article.new("; Term\n: Definition")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_definition)
    end

    it "classifies blank lines" do
      article = Wp2txt::Article.new("Text\n\nMore text")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_blank)
    end

    it "handles multi-line templates" do
      article = Wp2txt::Article.new(nested_templates)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_ml_template)
    end

    it "handles table content" do
      article = Wp2txt::Article.new(table_content)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_table)
    end

    it "detects redirects" do
      article = Wp2txt::Article.new("#REDIRECT [[Other Page]]")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_redirect)
    end
  end

  describe "#categories" do
    it "extracts English categories" do
      article = Wp2txt::Article.new(english_article)
      categories = article.categories.flatten
      expect(categories).to include("Tests")
    end

    # Tests for multilingual category extraction
    # Will fail until multilingual support is implemented
    # it "extracts Japanese categories" do
    #   article = Wp2txt::Article.new(japanese_article)
    #   categories = article.categories.flatten
    #   expect(categories).to include("テスト")
    # end

    it "extracts multiple categories from one article" do
      article = Wp2txt::Article.new(english_article)
      categories = article.categories.flatten
      expect(categories.size).to be >= 1
    end
  end

  describe "edge cases" do
    it "handles malformed markup gracefully" do
      # This test exposes the exit bug in convert_characters
      expect { Wp2txt::Article.new(malformed_markup) }.not_to raise_error
    end

    it "handles deeply nested templates" do
      # This test exposes the exit bug in convert_characters
      expect { Wp2txt::Article.new(deeply_nested) }.not_to raise_error
    end

    it "handles empty input" do
      article = Wp2txt::Article.new("")
      expect(article.elements).to be_empty
    end

    it "handles whitespace-only input" do
      article = Wp2txt::Article.new("   \n   \n   ")
      expect { article }.not_to raise_error
    end
  end

  describe "title handling" do
    it "stores the article title" do
      article = Wp2txt::Article.new("Content", "Test Title")
      expect(article.title).to eq "Test Title"
    end

    it "strips whitespace from title" do
      article = Wp2txt::Article.new("Content", "  Title  ")
      expect(article.title).to eq "Title"
    end
  end

  describe "multilingual content" do
    it "handles Japanese content" do
      expect { Wp2txt::Article.new(japanese_article) }.not_to raise_error
    end

    it "handles German content" do
      expect { Wp2txt::Article.new(german_article) }.not_to raise_error
    end

    it "handles Chinese content" do
      expect { Wp2txt::Article.new(chinese_article) }.not_to raise_error
    end

    it "handles Russian content" do
      expect { Wp2txt::Article.new(russian_article) }.not_to raise_error
    end

    it "handles Korean content" do
      expect { Wp2txt::Article.new(korean_article) }.not_to raise_error
    end

    it "handles Arabic content" do
      expect { Wp2txt::Article.new(arabic_article) }.not_to raise_error
    end
  end

  describe "multiline structures" do
    it "handles multiline templates" do
      wiki = "{{Infobox\n|name = Test\n|value = 123\n}}"
      article = Wp2txt::Article.new(wiki)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_ml_template)
    end

    it "handles multiline links" do
      wiki = "[[File:Image.jpg|thumb|Description\nthat spans\nmultiple lines]]"
      article = Wp2txt::Article.new(wiki)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_ml_link)
    end

    it "handles source code blocks" do
      wiki = "<source lang=\"ruby\">\ndef hello\n  puts 'world'\nend\n</source>"
      article = Wp2txt::Article.new(wiki)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_source)
    end

    it "handles multiline source blocks starting mid-content" do
      # Source block that starts in middle of content
      wiki = "text before\n<source lang=\"ruby\">\ncode here\n</source>\ntext after"
      article = Wp2txt::Article.new(wiki)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_source)
    end

    it "handles math blocks" do
      wiki = "<math>\nx = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}\n</math>"
      article = Wp2txt::Article.new(wiki)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_math)
    end

    it "handles single-line math blocks with content" do
      wiki = "formula: <math>E = mc^2</math> explained"
      article = Wp2txt::Article.new(wiki)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_math)
    end

    it "handles inputbox blocks" do
      wiki = "<inputbox>\ntype=search\nwidth=30\n</inputbox>"
      article = Wp2txt::Article.new(wiki)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_inputbox)
    end

    it "handles single-line inputbox with content" do
      wiki = "search: <inputbox>type=search</inputbox> here"
      article = Wp2txt::Article.new(wiki)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_inputbox)
    end

    it "handles HTML tables" do
      wiki = "<table>\n<tr><td>Cell</td></tr>\n</table>"
      article = Wp2txt::Article.new(wiki)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_htable)
    end

    it "handles single-line HTML tables with content" do
      wiki = "data: <table><tr><td>x</td></tr></table> end"
      article = Wp2txt::Article.new(wiki)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_htable)
    end
  end

  describe "pre-formatted text" do
    it "classifies pre-formatted text" do
      article = Wp2txt::Article.new(" preformatted text")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_pre)
    end
  end

  describe "strip_tmarker option" do
    it "strips list markers when enabled" do
      article = Wp2txt::Article.new("* List item", "", true)
      content = article.elements.find { |e| e.first == :mw_unordered }&.last
      expect(content).not_to start_with("*")
    end

    it "preserves list markers when disabled" do
      article = Wp2txt::Article.new("* List item", "", false)
      content = article.elements.find { |e| e.first == :mw_unordered }&.last
      expect(content).to start_with("*")
    end

    it "strips definition markers when enabled" do
      article = Wp2txt::Article.new(": Definition", "", true)
      content = article.elements.find { |e| e.first == :mw_definition }&.last
      expect(content).not_to start_with(":")
    end

    it "strips pre markers when enabled" do
      article = Wp2txt::Article.new(" preformatted", "", true)
      content = article.elements.find { |e| e.first == :mw_pre }&.last
      # Pre marker is the leading space; when stripped, content should not have it
      expect(content&.strip).to eq("preformatted")
    end

    it "strips ordered list markers when enabled" do
      article = Wp2txt::Article.new("# Numbered", "", true)
      content = article.elements.find { |e| e.first == :mw_ordered }&.last
      expect(content).not_to start_with("#")
    end
  end

  describe "isolated elements" do
    it "detects isolated templates" do
      article = Wp2txt::Article.new("{{stub}}")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_isolated_template)
    end

    it "detects isolated tags with content" do
      # ISOLATED_TAG_REGEX matches tags with content between them
      # Using <span> which is not removed by remove_html
      article = Wp2txt::Article.new("<span>content</span>")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_isolated_tag)
    end
  end

  describe "link handling" do
    it "detects standalone link lines" do
      article = Wp2txt::Article.new("[[Link Target]]")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_link)
    end
  end

  describe "multilingual redirects" do
    it "detects German redirect" do
      article = Wp2txt::Article.new("#WEITERLEITUNG [[Ziel]]")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_redirect)
    end

    it "detects French redirect" do
      article = Wp2txt::Article.new("#REDIRECTION [[Cible]]")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_redirect)
    end

    it "detects Japanese redirect" do
      article = Wp2txt::Article.new("#転送 [[転送先]]")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_redirect)
    end

    it "detects Russian redirect" do
      article = Wp2txt::Article.new("#ПЕРЕНАПРАВЛЕНИЕ [[Цель]]")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_redirect)
    end

    it "detects Chinese redirect" do
      article = Wp2txt::Article.new("#重定向 [[目标]]")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_redirect)
    end
  end

  describe "multilingual categories" do
    it "extracts Japanese categories" do
      article = Wp2txt::Article.new("[[カテゴリ:テスト]]")
      categories = article.categories.flatten
      expect(categories).to include("テスト")
    end

    it "extracts German categories" do
      article = Wp2txt::Article.new("[[Kategorie:Test]]")
      categories = article.categories.flatten
      expect(categories).to include("Test")
    end

    it "extracts French categories" do
      article = Wp2txt::Article.new("[[Catégorie:Test]]")
      categories = article.categories.flatten
      expect(categories).to include("Test")
    end

    it "extracts Russian categories" do
      article = Wp2txt::Article.new("[[Категория:Тест]]")
      categories = article.categories.flatten
      expect(categories).to include("Тест")
    end

    it "extracts Chinese simplified categories" do
      article = Wp2txt::Article.new("[[分类:测试]]")
      categories = article.categories.flatten
      expect(categories).to include("测试")
    end

    it "extracts Chinese traditional categories" do
      article = Wp2txt::Article.new("[[分類:測試]]")
      categories = article.categories.flatten
      expect(categories).to include("測試")
    end
  end
end
