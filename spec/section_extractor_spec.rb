# frozen_string_literal: true

require "spec_helper"
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
end
