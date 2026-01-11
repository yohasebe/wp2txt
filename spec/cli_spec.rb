# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/wp2txt/cli"
require "tmpdir"

# Load the CLI app class for testing
require_relative "../lib/wp2txt"
require_relative "../lib/wp2txt/utils"

RSpec.describe Wp2txt::CLI do
  describe ".parse_options" do
    context "with --from-category option" do
      it "requires --lang" do
        suppress_stderr do
          expect do
            described_class.parse_options(["--from-category=Test"])
          end.to raise_error(SystemExit)
        end
      end

      it "cannot be used with --input" do
        Dir.mktmpdir do |dir|
          # Create a dummy file
          dummy_file = File.join(dir, "test.bz2")
          File.write(dummy_file, "test")

          suppress_stderr do
            expect do
              described_class.parse_options([
                "--from-category=Test",
                "--lang=en",
                "--input=#{dummy_file}",
                "-o", dir
              ])
            end.to raise_error(SystemExit)
          end
        end
      end

      it "cannot be used with --articles" do
        Dir.mktmpdir do |dir|
          suppress_stderr do
            expect do
              described_class.parse_options([
                "--from-category=Test",
                "--lang=en",
                "--articles=Article1",
                "-o", dir
              ])
            end.to raise_error(SystemExit)
          end
        end
      end

      it "accepts valid options" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--from-category=Japanese cities",
            "--lang=en",
            "--depth=2",
            "-o", dir
          ])

          expect(opts[:from_category]).to eq "Japanese cities"
          expect(opts[:lang]).to eq "en"
          expect(opts[:depth]).to eq 2
        end
      end
    end

    context "with --depth option" do
      it "defaults to 0" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--from-category=Test",
            "--lang=en",
            "-o", dir
          ])

          expect(opts[:depth]).to eq 0
        end
      end

      it "rejects negative values" do
        Dir.mktmpdir do |dir|
          suppress_stderr do
            expect do
              described_class.parse_options([
                "--from-category=Test",
                "--lang=en",
                "--depth=-1",
                "-o", dir
              ])
            end.to raise_error(SystemExit)
          end
        end
      end

      it "warns when depth > 3" do
        Dir.mktmpdir do |dir|
          expect do
            described_class.parse_options([
              "--from-category=Test",
              "--lang=en",
              "--depth=4",
              "-o", dir
            ])
          end.to output(/Warning.*depth.*3/i).to_stderr
        end
      end
    end

    context "with --dry-run option" do
      it "requires --from-category" do
        Dir.mktmpdir do |dir|
          suppress_stderr do
            expect do
              described_class.parse_options([
                "--lang=en",
                "--dry-run",
                "-o", dir
              ])
            end.to raise_error(SystemExit)
          end
        end
      end

      it "works with --from-category" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--from-category=Test",
            "--lang=en",
            "--dry-run",
            "-o", dir
          ])

          expect(opts[:dry_run]).to be true
        end
      end
    end

    context "with --yes option" do
      it "requires --from-category" do
        Dir.mktmpdir do |dir|
          suppress_stderr do
            expect do
              described_class.parse_options([
                "--lang=en",
                "--yes",
                "-o", dir
              ])
            end.to raise_error(SystemExit)
          end
        end
      end

      it "works with --from-category" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--from-category=Test",
            "--lang=en",
            "--yes",
            "-o", dir
          ])

          expect(opts[:yes]).to be true
        end
      end
    end

    context "with --update-cache option" do
      it "defaults to false" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--from-category=Test",
            "--lang=en",
            "-o", dir
          ])

          expect(opts[:update_cache]).to be false
        end
      end

      it "can be set to true" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--from-category=Test",
            "--lang=en",
            "--update-cache",
            "-o", dir
          ])

          expect(opts[:update_cache]).to be true
        end
      end

      it "accepts short form -U" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--from-category=Test",
            "--lang=en",
            "-U",
            "-o", dir
          ])

          expect(opts[:update_cache]).to be true
        end
      end
    end

    context "with section extraction options" do
      it "parses --sections option" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--lang=en",
            "--sections=summary,Plot,Reception",
            "-o", dir
          ])

          expect(opts[:sections]).to eq("summary,Plot,Reception")
        end
      end

      it "parses --no-section-aliases option" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--lang=en",
            "--sections=Plot",
            "--no-section-aliases",
            "-o", dir
          ])

          expect(opts[:no_section_aliases]).to be true
        end
      end

      it "parses --show-matched-sections option" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--lang=en",
            "--sections=Plot",
            "--show-matched-sections",
            "--format=json",
            "-o", dir
          ])

          expect(opts[:show_matched_sections]).to be true
        end
      end

      it "rejects --show-matched-sections without JSON format" do
        Dir.mktmpdir do |dir|
          suppress_stderr do
            expect do
              described_class.parse_options([
                "--lang=en",
                "--sections=Plot",
                "--show-matched-sections",
                "--format=text",
                "-o", dir
              ])
            end.to raise_error(SystemExit)
          end
        end
      end

      it "parses --section-stats option" do
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--lang=en",
            "--section-stats",
            "-o", dir
          ])

          expect(opts[:section_stats]).to be true
        end
      end

      it "rejects --section-stats with --sections" do
        Dir.mktmpdir do |dir|
          suppress_stderr do
            expect do
              described_class.parse_options([
                "--lang=en",
                "--section-stats",
                "--sections=Plot",
                "-o", dir
              ])
            end.to raise_error(SystemExit)
          end
        end
      end

      it "rejects --section-stats with --metadata-only" do
        Dir.mktmpdir do |dir|
          suppress_stderr do
            expect do
              described_class.parse_options([
                "--lang=en",
                "--section-stats",
                "--metadata-only",
                "-o", dir
              ])
            end.to raise_error(SystemExit)
          end
        end
      end
    end

    context "with --alias-file option" do
      let(:temp_dir) { Dir.mktmpdir }
      let(:alias_file) { File.join(temp_dir, "aliases.yml") }

      after { FileUtils.remove_entry(temp_dir) }

      it "parses --alias-file option" do
        File.write(alias_file, "Plot:\n  - Synopsis\n")
        Dir.mktmpdir do |dir|
          opts = described_class.parse_options([
            "--lang=en",
            "--sections=Plot",
            "--alias-file=#{alias_file}",
            "-o", dir
          ])

          expect(opts[:alias_file]).to eq(alias_file)
        end
      end

      it "rejects non-existent alias file" do
        Dir.mktmpdir do |dir|
          suppress_stderr do
            expect do
              described_class.parse_options([
                "--lang=en",
                "--sections=Plot",
                "--alias-file=/nonexistent/file.yml",
                "-o", dir
              ])
            end.to raise_error(SystemExit)
          end
        end
      end

      it "rejects invalid YAML alias file" do
        File.write(alias_file, "invalid: yaml: {{")
        Dir.mktmpdir do |dir|
          suppress_stderr do
            expect do
              described_class.parse_options([
                "--lang=en",
                "--sections=Plot",
                "--alias-file=#{alias_file}",
                "-o", dir
              ])
            end.to raise_error(SystemExit)
          end
        end
      end
    end
  end
end

# Test the WpApp class methods
class TestWpApp
  include Wp2txt

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
    else
      nil
    end
  end
end

RSpec.describe "CLI format_article" do
  let(:app) { TestWpApp.new }

  let(:sample_wiki) do
    <<~WIKI
      '''Test Article''' is about [[testing]].

      == Section One ==
      This is paragraph one.

      == Section Two ==
      This is paragraph two.

      [[Category:Testing]]
      [[Category:Examples]]
    WIKI
  end

  let(:article) { Wp2txt::Article.new(sample_wiki, "Test Article") }

  let(:default_config) do
    {
      title: true,
      heading: true,
      list: false,
      table: false,
      redirect: false,
      category: true,
      category_only: false,
      summary_only: false
    }
  end

  describe "format_with_categories" do
    it "includes both body text and categories" do
      result = app.format_article(article, default_config)

      # Should include title
      expect(result).to include("[[Test Article]]")

      # Should include body text
      expect(result).to include("is about")
      expect(result).to include("Section One")
      expect(result).to include("paragraph one")

      # Should include categories
      expect(result).to include("CATEGORIES:")
      expect(result).to include("Testing")
      expect(result).to include("Examples")
    end

    it "places categories after body text" do
      result = app.format_article(article, default_config)

      body_position = result.index("paragraph")
      categories_position = result.index("CATEGORIES:")

      expect(categories_position).to be > body_position
    end
  end

  describe "format_category_only" do
    it "outputs only title and categories without body" do
      config = default_config.merge(category_only: true)
      result = app.format_article(article, config)

      # Should include title and categories
      expect(result).to include("Test Article")
      expect(result).to include("Testing")

      # Should NOT include body text
      expect(result).not_to include("paragraph")
      expect(result).not_to include("Section One")
    end
  end

  describe "format_full_article without categories" do
    it "outputs body without categories section when article has no categories" do
      wiki_no_categories = "'''Simple''' article with no categories."
      article_no_cat = Wp2txt::Article.new(wiki_no_categories, "Simple")

      result = app.format_article(article_no_cat, default_config)

      expect(result).to include("[[Simple]]")
      expect(result).to include("article with no categories")
      expect(result).not_to include("CATEGORIES:")
    end
  end

  describe "summary_only mode" do
    it "excludes headings when summary_only is true" do
      config = default_config.merge(summary_only: true)
      result = app.format_article(article, config)

      # Should include first paragraph
      expect(result).to include("is about")

      # Should NOT include section headings
      expect(result).not_to include("Section One")
      expect(result).not_to include("Section Two")
    end
  end

  describe "heading option" do
    it "excludes headings when heading is false" do
      config = default_config.merge(heading: false)
      result = app.format_article(article, config)

      # Should include paragraph content
      expect(result).to include("is about")

      # Should NOT include headings
      expect(result).not_to include("Section One")
    end
  end

  describe "redirect handling" do
    let(:redirect_wiki) { "#REDIRECT [[Target Article]]" }
    let(:redirect_article) { Wp2txt::Article.new(redirect_wiki, "Redirect Test") }

    it "excludes redirect by default" do
      result = app.format_article(redirect_article, default_config)
      expect(result).not_to include("REDIRECT")
      expect(result).not_to include("Target Article")
    end

    it "includes redirect when redirect option is true" do
      config = default_config.merge(redirect: true, category: false)
      result = app.format_article(redirect_article, config)
      expect(result).to include("REDIRECT")
    end
  end
end

RSpec.describe "End-to-end article processing" do
  include Wp2txt

  let(:complex_article) do
    <<~WIKI
      {{Infobox
      |name = Test
      }}
      '''Complex Article''' is a [[test]] with '''bold''' and ''italic''.

      == History ==
      The history section with a [[link|display text]].

      == Features ==
      * Feature one
      * Feature two

      {| class="wikitable"
      |-
      | Cell 1 || Cell 2
      |}

      == References ==
      <ref>Citation</ref>

      [[Category:Complex]]
      [[Category:Test Articles]]
    WIKI
  end

  it "correctly processes complex articles with categories" do
    article = Wp2txt::Article.new(complex_article, "Complex Article")

    # Article should have elements
    expect(article.elements).not_to be_empty

    # Article should have categories
    expect(article.categories.flatten).to include("Complex")
    expect(article.categories.flatten).to include("Test Articles")

    # Article should have headings
    types = article.elements.map(&:first)
    expect(types).to include(:mw_heading)
    expect(types).to include(:mw_paragraph)
  end

  it "extracts body text correctly through format_wiki" do
    article = Wp2txt::Article.new(complex_article, "Complex Article")

    # Find paragraph elements and format them
    paragraphs = article.elements.select { |e| e.first == :mw_paragraph }
    expect(paragraphs).not_to be_empty

    # Format the first paragraph
    first_para = paragraphs.first.last
    formatted = format_wiki(first_para)

    # Should contain the text without wiki markup
    expect(formatted).to include("Complex Article")
    expect(formatted).to include("test")

    # Should not contain raw wiki markup
    expect(formatted).not_to include("'''")
    expect(formatted).not_to include("[[")
  end
end
