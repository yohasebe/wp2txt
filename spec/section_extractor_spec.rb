# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../lib/wp2txt/article"
require_relative "../lib/wp2txt/section_extractor"

RSpec.describe Wp2txt::SectionExtractor do
  let(:sample_wiki_text) do
    <<~WIKI
      This is the summary text before any headings.

      == Early life ==
      Born in Tokyo, Japan.

      == Career ==
      Started working in 2010.

      === Publications ===
      First paper (2010)
      Second paper (2015)

      == Reception ==
      The work was well received.

      == References ==
      <ref>Citation</ref>

      [[Category:Scientists]]
      [[Category:1990 births]]
    WIKI
  end

  let(:article) { Wp2txt::Article.new(sample_wiki_text, "Test Person") }
  let(:extractor) { described_class.new }

  describe "#extract_headings" do
    it "extracts all section headings" do
      headings = extractor.extract_headings(article)
      expect(headings).to eq(["Early life", "Career", "Publications", "Reception", "References"])
    end

    it "returns empty array for article without headings" do
      simple_article = Wp2txt::Article.new("Just some text.", "Simple")
      headings = extractor.extract_headings(simple_article)
      expect(headings).to eq([])
    end
  end

  describe "#extract_headings_with_levels" do
    it "extracts headings with their levels" do
      headings = extractor.extract_headings_with_levels(article)

      expect(headings).to include(
        { name: "Early life", level: 2 },
        { name: "Career", level: 2 },
        { name: "Publications", level: 3 },
        { name: "Reception", level: 2 }
      )
    end

    it "correctly identifies level 3 subsections" do
      headings = extractor.extract_headings_with_levels(article)
      publications = headings.find { |h| h[:name] == "Publications" }
      expect(publications[:level]).to eq(3)
    end
  end

  describe "#extract_summary" do
    it "extracts text before first heading" do
      summary = extractor.extract_summary(article)
      expect(summary).to include("This is the summary text")
    end

    it "returns nil for article starting with heading" do
      no_summary_article = Wp2txt::Article.new("== Heading ==\nContent", "No Summary")
      summary = extractor.extract_summary(no_summary_article)
      expect(summary).to be_nil
    end
  end

  describe "#extract_sections with targets" do
    context "when extracting summary and specific sections" do
      let(:extractor) { described_class.new(["summary", "Career", "Plot"]) }

      it "includes summary when requested" do
        sections = extractor.extract_sections(article)
        expect(sections["summary"]).to include("summary text")
      end

      it "includes matching sections" do
        sections = extractor.extract_sections(article)
        expect(sections["Career"]).to include("Started working")
      end

      it "returns nil for non-existent sections" do
        sections = extractor.extract_sections(article)
        expect(sections["Plot"]).to be_nil
      end

      it "includes subsections in parent section" do
        sections = extractor.extract_sections(article)
        expect(sections["Career"]).to include("First paper")
      end
    end

    context "with minimum length filter" do
      let(:extractor) { described_class.new(["summary", "Career"], min_length: 50) }

      it "filters out short sections but keeps long ones" do
        sections = extractor.extract_sections(article)
        # Career section with subsections should be long enough (>50 chars)
        expect(sections["Career"]).not_to be_nil
      end

      it "filters out sections shorter than min_length" do
        strict_extractor = described_class.new(["summary", "Early life"], min_length: 100)
        sections = strict_extractor.extract_sections(article)
        # Early life section is short ("Born in Tokyo, Japan.")
        expect(sections["Early life"]).to be_nil
      end
    end
  end

  describe "alias matching" do
    context "with default aliases" do
      let(:wiki_with_synopsis) do
        <<~WIKI
          Summary.

          == Synopsis ==
          The story follows...
        WIKI
      end
      let(:synopsis_article) { Wp2txt::Article.new(wiki_with_synopsis, "Movie") }
      let(:extractor) { described_class.new(["Plot"]) }

      it "matches Synopsis as alias for Plot" do
        sections = extractor.extract_sections(synopsis_article)
        expect(sections["Plot"]).to include("story follows")
      end
    end

    context "with aliases disabled" do
      let(:wiki_with_synopsis) do
        <<~WIKI
          Summary.

          == Synopsis ==
          The story follows...
        WIKI
      end
      let(:synopsis_article) { Wp2txt::Article.new(wiki_with_synopsis, "Movie") }
      let(:extractor) { described_class.new(["Plot"], use_aliases: false) }

      it "does not match Synopsis when aliases are disabled" do
        sections = extractor.extract_sections(synopsis_article)
        expect(sections["Plot"]).to be_nil
      end
    end
  end

  describe "bidirectional alias matching" do
    let(:wiki_with_plot) do
      <<~WIKI
        Summary.

        == Plot ==
        The story begins...
      WIKI
    end
    let(:plot_article) { Wp2txt::Article.new(wiki_with_plot, "Film") }

    let(:wiki_with_synopsis) do
      <<~WIKI
        Summary.

        == Synopsis ==
        The story follows...
      WIKI
    end
    let(:synopsis_article) { Wp2txt::Article.new(wiki_with_synopsis, "Movie") }

    let(:wiki_with_reviews) do
      <<~WIKI
        Summary.

        == Reviews ==
        Critics praised...
      WIKI
    end
    let(:reviews_article) { Wp2txt::Article.new(wiki_with_reviews, "Album") }

    context "when target is canonical name" do
      let(:extractor) { described_class.new(["Plot"]) }

      it "matches alias heading (Synopsis)" do
        sections = extractor.extract_sections(synopsis_article)
        expect(sections["Plot"]).to include("story follows")
      end
    end

    context "when target is an alias name" do
      let(:extractor) { described_class.new(["Synopsis"]) }

      it "matches canonical heading (Plot)" do
        sections = extractor.extract_sections(plot_article)
        expect(sections["Synopsis"]).to include("story begins")
      end
    end

    context "when target is one alias and heading is another alias in the same group" do
      let(:extractor) { described_class.new(["Reviews"]) }

      it "matches Critical reception heading via shared alias group" do
        wiki = "== Critical reception ==\nWell received."
        art = Wp2txt::Article.new(wiki, "Work")
        sections = extractor.extract_sections(art)
        expect(sections["Reviews"]).to include("Well received")
      end
    end

    context "when aliases are disabled" do
      let(:extractor) { described_class.new(["Synopsis"], use_aliases: false) }

      it "does not match canonical name (Plot)" do
        sections = extractor.extract_sections(plot_article)
        expect(sections["Synopsis"]).to be_nil
      end
    end
  end

  describe "case-insensitive matching" do
    let(:extractor) { described_class.new(["early life", "CAREER"]) }

    it "matches sections regardless of case" do
      sections = extractor.extract_sections(article)
      expect(sections["early life"]).to include("Born in Tokyo")
      expect(sections["CAREER"]).to include("Started working")
    end
  end

  describe "#has_matching_sections?" do
    context "with matching sections" do
      let(:extractor) { described_class.new(["Career"]) }

      it "returns true" do
        expect(extractor.has_matching_sections?(article)).to be true
      end
    end

    context "with no matching sections" do
      let(:extractor) { described_class.new(["Plot", "Gameplay"]) }

      it "returns false" do
        expect(extractor.has_matching_sections?(article)).to be false
      end
    end

    context "when summary is requested and exists" do
      let(:extractor) { described_class.new(["summary"]) }

      it "returns true" do
        expect(extractor.has_matching_sections?(article)).to be true
      end
    end
  end

  describe "#should_skip?" do
    context "with skip_empty: false (default)" do
      let(:extractor) { described_class.new(["Plot"], skip_empty: false) }

      it "returns false even when no sections match" do
        expect(extractor.should_skip?(article)).to be false
      end
    end

    context "with skip_empty: true" do
      let(:extractor) { described_class.new(["Plot"], skip_empty: true) }

      it "returns true when no sections match" do
        expect(extractor.should_skip?(article)).to be true
      end

      it "returns false when sections match" do
        extractor_with_match = described_class.new(["Career"], skip_empty: true)
        expect(extractor_with_match.should_skip?(article)).to be false
      end
    end
  end

  describe "alias file loading" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:alias_file) { File.join(temp_dir, "aliases.yml") }

    after { FileUtils.remove_entry(temp_dir) }

    context "with valid YAML alias file" do
      before do
        File.write(alias_file, <<~YAML)
          Career:
            - Work history
            - Employment
          Plot:
            - Synopsis
            - Story
        YAML
      end

      it "loads aliases from file" do
        aliases = described_class.load_aliases_from_file(alias_file)
        expect(aliases["Career"]).to eq(["Work history", "Employment"])
        expect(aliases["Plot"]).to eq(["Synopsis", "Story"])
      end

      it "merges file aliases with defaults" do
        extractor = described_class.new(["Plot"], alias_file: alias_file)
        # Should have both default "Synopsis" and file "Story" as aliases
        wiki_with_story = <<~WIKI
          == Story ==
          The story begins...
        WIKI
        story_article = Wp2txt::Article.new(wiki_with_story, "Film")
        sections = extractor.extract_sections(story_article)
        expect(sections["Plot"]).to include("story begins")
      end
    end

    context "with non-existent file" do
      it "returns empty hash" do
        aliases = described_class.load_aliases_from_file("/nonexistent/file.yml")
        expect(aliases).to eq({})
      end
    end

    context "with invalid YAML" do
      before { File.write(alias_file, "invalid: yaml: syntax: {{") }

      it "returns empty hash" do
        aliases = described_class.load_aliases_from_file(alias_file)
        expect(aliases).to eq({})
      end
    end
  end

  describe "matched sections tracking" do
    let(:wiki_with_synopsis) do
      <<~WIKI
        Summary text.
        == Synopsis ==
        The story begins...
      WIKI
    end
    let(:synopsis_article) { Wp2txt::Article.new(wiki_with_synopsis, "Movie") }

    context "with track_matches enabled" do
      let(:extractor) { described_class.new(["Plot"], track_matches: true) }

      it "records alias matches" do
        extractor.extract_sections(synopsis_article)
        expect(extractor.matched_sections["Plot"]).to eq("Synopsis")
      end
    end

    context "with track_matches disabled (default)" do
      let(:extractor) { described_class.new(["Plot"], track_matches: false) }

      it "does not record matches" do
        extractor.extract_sections(synopsis_article)
        expect(extractor.matched_sections).to be_empty
      end
    end

    context "with direct match (different case)" do
      let(:wiki_text) { "== plot ==\nContent here." }
      let(:plot_article) { Wp2txt::Article.new(wiki_text, "Film") }
      let(:extractor) { described_class.new(["Plot"], track_matches: true) }

      it "records case-different direct matches" do
        extractor.extract_sections(plot_article)
        expect(extractor.matched_sections["Plot"]).to eq("plot")
      end
    end
  end
end

RSpec.describe Wp2txt::SectionStatsCollector do
  let(:sample_wiki_text) do
    <<~WIKI
      Summary.
      == Early life ==
      Content.
      == Career ==
      Content.
    WIKI
  end

  let(:another_wiki_text) do
    <<~WIKI
      Summary.
      == Career ==
      Content.
      == Reception ==
      Content.
    WIKI
  end

  let(:article1) { Wp2txt::Article.new(sample_wiki_text, "Person 1") }
  let(:article2) { Wp2txt::Article.new(another_wiki_text, "Work 1") }

  describe "#process" do
    it "counts articles" do
      collector = described_class.new
      collector.process(article1)
      collector.process(article2)
      expect(collector.total_articles).to eq(2)
    end

    it "counts section occurrences" do
      collector = described_class.new
      collector.process(article1)
      collector.process(article2)

      expect(collector.section_counts["Career"]).to eq(2)
      expect(collector.section_counts["Early life"]).to eq(1)
      expect(collector.section_counts["Reception"]).to eq(1)
    end
  end

  describe "#top_sections" do
    it "returns sections sorted by count" do
      collector = described_class.new
      collector.process(article1)
      collector.process(article2)

      top = collector.top_sections(2)
      expect(top.first["name"]).to eq("Career")
      expect(top.first["count"]).to eq(2)
      expect(top.length).to eq(2)
    end
  end

  describe "#to_hash" do
    it "returns statistics as hash" do
      collector = described_class.new
      collector.process(article1)
      collector.process(article2)

      result = collector.to_hash(top_n: 5)
      expect(result["total_articles"]).to eq(2)
      expect(result["section_counts"]).to be_a(Hash)
      expect(result["top_sections"]).to be_an(Array)
    end
  end

  describe "#to_json" do
    it "returns valid JSON" do
      collector = described_class.new
      collector.process(article1)

      json = collector.to_json
      parsed = JSON.parse(json)
      expect(parsed["total_articles"]).to eq(1)
    end
  end
end
