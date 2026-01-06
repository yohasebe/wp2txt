# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/wp2txt"
require_relative "../lib/wp2txt/utils"

# Simulate CLI app for testing options
class CLITestApp
  include Wp2txt

  # Default configuration matching bin/wp2txt defaults
  DEFAULT_CONFIG = {
    title: true,
    heading: true,
    list: false,
    table: false,
    redirect: false,
    category: true,
    category_only: false,
    summary_only: false,
    marker: true
  }.freeze

  def self.default_config
    DEFAULT_CONFIG.dup
  end

  def format_article(article, config)
    article.title = format_wiki(article.title, config)

    if config[:category_only]
      format_category_only(article)
    elsif config[:category] && !article.categories.empty?
      format_with_categories(article, config)
    else
      format_full_article(article, config)
    end
  end

  def format_category_only(article)
    title = "#{article.title}\t"
    contents = article.categories.join(", ")
    contents << "\n"
    title + contents
  end

  def format_with_categories(article, config)
    title = "\n[[#{article.title}]]\n\n"
    contents = +""

    article.elements.each do |e|
      line = process_element(e, config)
      contents << line if line
    end

    contents << "\nCATEGORIES: "
    contents << article.categories.join(", ")
    contents << "\n\n"

    config[:title] ? title + contents : contents
  end

  def format_full_article(article, config)
    title = "\n[[#{article.title}]]\n\n"
    contents = +""

    article.elements.each do |e|
      line = process_element(e, config)
      contents << line if line
    end

    config[:title] ? title + contents : contents
  end

  def process_element(element, config)
    type, content = element
    case type
    when :mw_heading
      return nil if config[:summary_only]
      return nil unless config[:heading]

      content = format_wiki(content, config)
      content + "\n"
    when :mw_paragraph
      content = format_wiki(content, config)
      content + "\n"
    when :mw_table, :mw_htable
      return nil unless config[:table]

      content + "\n"
    when :mw_unordered, :mw_ordered, :mw_definition
      return nil unless config[:list]

      content + "\n"
    when :mw_redirect
      return nil unless config[:redirect]

      content + "\n\n"
    when :mw_isolated_template, :mw_isolated_tag
      nil
    else
      nil
    end
  end
end

RSpec.describe "CLI Options" do
  let(:app) { CLITestApp.new }

  # Standard test article with various elements
  let(:full_article_wiki) do
    <<~WIKI
      '''Test Article''' is about [[testing]] software.

      == Introduction ==
      This is the introduction paragraph.

      == Features ==
      The features section.

      * Feature one
      * Feature two
      # Step one
      # Step two

      {| class="wikitable"
      |-
      | Cell 1 || Cell 2
      |}

      == See Also ==
      Related content here.

      [[Category:Software]]
      [[Category:Testing]]
    WIKI
  end

  let(:redirect_wiki) { "#REDIRECT [[Target Page]]" }

  let(:article) { Wp2txt::Article.new(full_article_wiki, "Test Article") }
  let(:redirect_article) { Wp2txt::Article.new(redirect_wiki, "Redirect Source") }

  describe "Default configuration values" do
    let(:defaults) { CLITestApp.default_config }

    it "title defaults to true" do
      expect(defaults[:title]).to be true
    end

    it "heading defaults to true" do
      expect(defaults[:heading]).to be true
    end

    it "list defaults to false" do
      expect(defaults[:list]).to be false
    end

    it "table defaults to false" do
      expect(defaults[:table]).to be false
    end

    it "redirect defaults to false" do
      expect(defaults[:redirect]).to be false
    end

    it "category defaults to true" do
      expect(defaults[:category]).to be true
    end

    it "category_only defaults to false" do
      expect(defaults[:category_only]).to be false
    end

    it "summary_only defaults to false" do
      expect(defaults[:summary_only]).to be false
    end

    it "marker defaults to true" do
      expect(defaults[:marker]).to be true
    end
  end

  describe "--title / -t option" do
    context "when title is true (default)" do
      it "includes article title in output" do
        config = CLITestApp.default_config
        result = app.format_article(article, config)

        expect(result).to include("[[Test Article]]")
      end
    end

    context "when title is false" do
      it "excludes article title from output" do
        config = CLITestApp.default_config.merge(title: false)
        result = app.format_article(article, config)

        expect(result).not_to include("[[Test Article]]")
      end

      it "still includes body content" do
        config = CLITestApp.default_config.merge(title: false)
        result = app.format_article(article, config)

        expect(result).to include("testing")
      end
    end
  end

  describe "--heading / -d option" do
    context "when heading is true (default)" do
      it "includes section headings in output" do
        config = CLITestApp.default_config
        result = app.format_article(article, config)

        expect(result).to include("Introduction")
        expect(result).to include("Features")
        expect(result).to include("See Also")
      end
    end

    context "when heading is false" do
      it "excludes section headings from output" do
        config = CLITestApp.default_config.merge(heading: false)
        result = app.format_article(article, config)

        expect(result).not_to include("Introduction")
        expect(result).not_to include("Features")
      end

      it "still includes paragraph content" do
        config = CLITestApp.default_config.merge(heading: false)
        result = app.format_article(article, config)

        expect(result).to include("introduction paragraph")
      end
    end
  end

  describe "--list / -l option" do
    context "when list is false (default)" do
      it "excludes list items from output" do
        config = CLITestApp.default_config
        result = app.format_article(article, config)

        expect(result).not_to include("Feature one")
        expect(result).not_to include("Step one")
      end
    end

    context "when list is true" do
      it "includes unordered list items" do
        config = CLITestApp.default_config.merge(list: true)
        result = app.format_article(article, config)

        expect(result).to include("Feature one")
        expect(result).to include("Feature two")
      end

      it "includes ordered list items" do
        config = CLITestApp.default_config.merge(list: true)
        result = app.format_article(article, config)

        expect(result).to include("Step one")
        expect(result).to include("Step two")
      end
    end
  end

  describe "--table option" do
    context "when table is false (default)" do
      it "excludes table content from output" do
        config = CLITestApp.default_config
        result = app.format_article(article, config)

        # Table raw content should not appear
        expect(result).not_to include("Cell 1")
      end
    end

    context "when table is true" do
      it "includes table content in output" do
        config = CLITestApp.default_config.merge(table: true)
        result = app.format_article(article, config)

        expect(result).to include("Cell 1")
      end
    end
  end

  describe "--redirect / -e option" do
    context "when redirect is false (default)" do
      it "excludes redirect information" do
        config = CLITestApp.default_config.merge(category: false)
        result = app.format_article(redirect_article, config)

        expect(result).not_to include("REDIRECT")
        expect(result).not_to include("Target Page")
      end
    end

    context "when redirect is true" do
      it "includes redirect information" do
        config = CLITestApp.default_config.merge(redirect: true, category: false)
        result = app.format_article(redirect_article, config)

        expect(result).to include("REDIRECT")
      end
    end
  end

  describe "--category / -a option" do
    context "when category is true (default)" do
      it "includes categories in output" do
        config = CLITestApp.default_config
        result = app.format_article(article, config)

        expect(result).to include("CATEGORIES:")
        expect(result).to include("Software")
        expect(result).to include("Testing")
      end

      it "also includes body text" do
        config = CLITestApp.default_config
        result = app.format_article(article, config)

        expect(result).to include("testing")
        expect(result).to include("introduction paragraph")
      end
    end

    context "when category is false" do
      it "excludes categories section from output" do
        config = CLITestApp.default_config.merge(category: false)
        result = app.format_article(article, config)

        expect(result).not_to include("CATEGORIES:")
      end

      it "still includes body text" do
        config = CLITestApp.default_config.merge(category: false)
        result = app.format_article(article, config)

        expect(result).to include("testing")
      end
    end
  end

  describe "--category-only / -g option" do
    context "when category_only is false (default)" do
      it "includes full article content" do
        config = CLITestApp.default_config
        result = app.format_article(article, config)

        expect(result).to include("testing")
        expect(result).to include("Introduction")
      end
    end

    context "when category_only is true" do
      it "outputs only title and categories" do
        config = CLITestApp.default_config.merge(category_only: true)
        result = app.format_article(article, config)

        expect(result).to include("Test Article")
        expect(result).to include("Software")
        expect(result).to include("Testing")
      end

      it "excludes body text" do
        config = CLITestApp.default_config.merge(category_only: true)
        result = app.format_article(article, config)

        expect(result).not_to include("introduction paragraph")
        expect(result).not_to include("Features")
      end

      it "uses tab-separated format" do
        config = CLITestApp.default_config.merge(category_only: true)
        result = app.format_article(article, config)

        expect(result).to include("\t")
      end
    end
  end

  describe "--summary-only / -s option" do
    context "when summary_only is false (default)" do
      it "includes all headings" do
        config = CLITestApp.default_config
        result = app.format_article(article, config)

        expect(result).to include("Introduction")
        expect(result).to include("Features")
        expect(result).to include("See Also")
      end
    end

    context "when summary_only is true" do
      it "excludes section headings" do
        config = CLITestApp.default_config.merge(summary_only: true)
        result = app.format_article(article, config)

        expect(result).not_to include("Introduction")
        expect(result).not_to include("Features")
      end

      it "includes first paragraph (summary)" do
        config = CLITestApp.default_config.merge(summary_only: true)
        result = app.format_article(article, config)

        expect(result).to include("testing")
      end

      it "includes categories if category option is true" do
        config = CLITestApp.default_config.merge(summary_only: true)
        result = app.format_article(article, config)

        expect(result).to include("CATEGORIES:")
      end
    end
  end

  describe "Option combinations" do
    it "category + title both false outputs only body" do
      config = CLITestApp.default_config.merge(category: false, title: false)
      result = app.format_article(article, config)

      expect(result).not_to include("[[Test Article]]")
      expect(result).not_to include("CATEGORIES:")
      expect(result).to include("testing")
    end

    it "summary_only + category outputs summary with categories" do
      config = CLITestApp.default_config.merge(summary_only: true, category: true)
      result = app.format_article(article, config)

      expect(result).to include("testing")
      expect(result).to include("CATEGORIES:")
      expect(result).not_to include("Introduction")
    end

    it "heading false + list true shows lists but not headings" do
      config = CLITestApp.default_config.merge(heading: false, list: true)
      result = app.format_article(article, config)

      expect(result).not_to include("Introduction")
      expect(result).to include("Feature one")
    end

    it "all content options enabled shows everything" do
      config = CLITestApp.default_config.merge(
        heading: true,
        list: true,
        table: true,
        redirect: true
      )
      result = app.format_article(article, config)

      expect(result).to include("Introduction")
      expect(result).to include("Feature one")
      expect(result).to include("Cell 1")
    end

    it "category_only takes precedence over other content options" do
      config = CLITestApp.default_config.merge(
        category_only: true,
        heading: true,
        list: true
      )
      result = app.format_article(article, config)

      # Should only have title and categories
      expect(result).to include("Test Article")
      expect(result).to include("Software")
      expect(result).not_to include("Introduction")
      expect(result).not_to include("Feature one")
    end
  end

  describe "Edge cases" do
    it "handles article with no categories when category is true" do
      wiki_no_cat = "'''Simple''' article without categories."
      article_no_cat = Wp2txt::Article.new(wiki_no_cat, "Simple")
      config = CLITestApp.default_config

      result = app.format_article(article_no_cat, config)

      # Should use format_full_article (no CATEGORIES section)
      expect(result).to include("[[Simple]]")
      expect(result).to include("article without categories")
      expect(result).not_to include("CATEGORIES:")
    end

    it "handles empty article" do
      empty_article = Wp2txt::Article.new("", "Empty")
      config = CLITestApp.default_config.merge(category: false)

      result = app.format_article(empty_article, config)

      expect(result).to include("[[Empty]]")
    end

    it "handles article with only categories" do
      cat_only_wiki = "[[Category:Test]][[Category:Example]]"
      cat_article = Wp2txt::Article.new(cat_only_wiki, "Categories Only")
      config = CLITestApp.default_config

      result = app.format_article(cat_article, config)

      expect(result).to include("CATEGORIES:")
      expect(result).to include("Test")
    end

    it "handles article with deeply nested markup" do
      nested_wiki = "{{outer|{{inner|{{deep|content}}}}}} and [[link|[[nested]]]]"
      nested_article = Wp2txt::Article.new(nested_wiki, "Nested")
      config = CLITestApp.default_config.merge(category: false)

      # Should not raise error
      expect { app.format_article(nested_article, config) }.not_to raise_error
    end

    it "handles article with special characters in title" do
      special_article = Wp2txt::Article.new("Content here.", "C++ Programming")
      config = CLITestApp.default_config.merge(category: false)

      result = app.format_article(special_article, config)
      expect(result).to include("C++ Programming")
    end

    it "handles Unicode content correctly" do
      unicode_wiki = "'''日本語記事''' は [[テスト]] です。\n[[カテゴリ:日本語]]"
      unicode_article = Wp2txt::Article.new(unicode_wiki, "日本語")
      config = CLITestApp.default_config

      result = app.format_article(unicode_article, config)

      expect(result).to include("日本語")
      expect(result.valid_encoding?).to be true
    end
  end
end

RSpec.describe "Article element type coverage" do
  include Wp2txt

  describe "All element types are parsed correctly" do
    it "detects :mw_heading" do
      article = Wp2txt::Article.new("== Heading ==", "Test")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_heading)
    end

    it "detects :mw_paragraph" do
      article = Wp2txt::Article.new("Simple paragraph text.", "Test")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_paragraph)
    end

    it "detects :mw_unordered" do
      article = Wp2txt::Article.new("* List item", "Test")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_unordered)
    end

    it "detects :mw_ordered" do
      article = Wp2txt::Article.new("# Numbered item", "Test")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_ordered)
    end

    it "detects :mw_definition" do
      article = Wp2txt::Article.new("; Term\n: Definition", "Test")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_definition)
    end

    it "detects :mw_table" do
      article = Wp2txt::Article.new("{| class=\"wikitable\"\n|-\n| Cell\n|}", "Test")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_table)
    end

    it "detects :mw_redirect" do
      article = Wp2txt::Article.new("#REDIRECT [[Target]]", "Test")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_redirect)
    end

    it "detects :mw_blank" do
      article = Wp2txt::Article.new("Text\n\nMore text", "Test")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_blank)
    end

    it "detects :mw_isolated_template" do
      article = Wp2txt::Article.new("{{Stub}}", "Test")
      types = article.elements.map(&:first)
      expect(types).to include(:mw_isolated_template)
    end
  end
end
