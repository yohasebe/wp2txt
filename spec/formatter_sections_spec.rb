# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../lib/wp2txt/article"
require_relative "../lib/wp2txt/formatter"

RSpec.describe "Formatter section extraction" do
  include Wp2txt::Formatter
  include Wp2txt

  let(:sample_wiki_text) do
    <<~WIKI
      '''The Godfather''' is a 1972 American crime film.

      == Plot ==
      The story of the Corleone crime family.

      == Cast ==
      * Marlon Brando as Vito Corleone
      * Al Pacino as Michael Corleone

      == Reception ==
      The film received critical acclaim.

      === Awards ===
      Won three Academy Awards.

      [[Category:1972 films]]
      [[Category:Crime films]]
    WIKI
  end

  let(:article) { Wp2txt::Article.new(sample_wiki_text, "The Godfather") }

  describe "format_article with sections" do
    context "structured JSON output" do
      let(:config) do
        {
          format: :json,
          sections: ["summary", "Plot", "Reception"],
          category: true
        }
      end

      it "returns sections object with each section" do
        result = format_article(article, config)
        expect(result).to be_a(Hash)
        expect(result["sections"]).to be_a(Hash)
        expect(result["sections"].keys).to include("summary", "Plot", "Reception")
      end

      it "includes summary text" do
        result = format_article(article, config)
        expect(result["sections"]["summary"]).to include("1972 American crime film")
      end

      it "includes section content" do
        result = format_article(article, config)
        expect(result["sections"]["Plot"]).to include("Corleone crime family")
      end

      it "includes subsections in parent section" do
        result = format_article(article, config)
        expect(result["sections"]["Reception"]).to include("Academy Awards")
      end

      it "includes categories" do
        result = format_article(article, config)
        expect(result["categories"]).to include("1972 films", "Crime films")
      end
    end

    context "combined JSON output" do
      let(:config) do
        {
          format: :json,
          sections: ["summary", "Plot"],
          section_output: "combined",
          category: true
        }
      end

      it "returns concatenated text" do
        result = format_article(article, config)
        expect(result["text"]).to include("crime film")
        expect(result["text"]).to include("Corleone")
      end

      it "includes sections_included array" do
        result = format_article(article, config)
        expect(result["sections_included"]).to eq(["summary", "Plot"])
      end
    end

    context "structured text output" do
      let(:config) do
        {
          format: :text,
          sections: ["summary", "Plot", "Cast"],
          category: true
        }
      end

      it "includes TITLE header" do
        result = format_article(article, config)
        expect(result).to include("TITLE: The Godfather")
      end

      it "includes SECTION labels" do
        result = format_article(article, config)
        expect(result).to include("SECTION [summary]:")
        expect(result).to include("SECTION [Plot]:")
        expect(result).to include("SECTION [Cast]:")
      end

      it "includes CATEGORIES footer" do
        result = format_article(article, config)
        expect(result).to include("CATEGORIES: 1972 films, Crime films")
      end
    end

    context "combined text output" do
      let(:config) do
        {
          format: :text,
          sections: ["summary", "Plot"],
          section_output: "combined",
          category: true
        }
      end

      it "includes SECTIONS header listing included sections" do
        result = format_article(article, config)
        expect(result).to include("SECTIONS: summary, Plot")
      end

      it "includes concatenated content" do
        result = format_article(article, config)
        expect(result).to include("crime film")
        expect(result).to include("Corleone")
      end
    end

    context "with non-existent sections" do
      let(:config) do
        {
          format: :json,
          sections: ["summary", "Gameplay", "Plot"],
          category: true
        }
      end

      it "returns nil for non-existent sections" do
        result = format_article(article, config)
        expect(result["sections"]["Gameplay"]).to be_nil
        expect(result["sections"]["Plot"]).not_to be_nil
      end
    end

    context "with min_section_length filter" do
      let(:config) do
        {
          format: :json,
          sections: ["summary", "Plot"],
          min_section_length: 100,
          category: true
        }
      end

      it "filters out short sections" do
        result = format_article(article, config)
        # Summary is short in this test
        expect(result["sections"]["summary"]).to be_nil
      end
    end

    context "with skip_empty option" do
      let(:no_match_config) do
        {
          format: :json,
          sections: ["Gameplay", "Soundtrack"],
          skip_empty: true,
          category: true
        }
      end

      it "returns nil for articles with no matching sections" do
        result = format_article(article, no_match_config)
        expect(result).to be_nil
      end
    end
  end

  describe "summary_only refactoring" do
    let(:config) do
      {
        format: :json,
        summary_only: true,
        category: true
      }
    end

    it "extracts only summary" do
      result = format_article(article, config)
      expect(result["text"]).to include("crime film")
      expect(result["text"]).not_to include("Corleone")
    end

    it "uses combined output mode" do
      result = format_article(article, config)
      expect(result["sections_included"]).to eq(["summary"])
    end
  end

  describe "alias matching in extraction" do
    let(:wiki_with_synopsis) do
      <<~WIKI
        A movie summary.

        == Synopsis ==
        The story follows the main character.

        [[Category:Films]]
      WIKI
    end

    let(:synopsis_article) { Wp2txt::Article.new(wiki_with_synopsis, "Test Movie") }

    let(:config) do
      {
        format: :json,
        sections: ["summary", "Plot"],
        category: true
      }
    end

    it "matches Synopsis as alias for Plot" do
      result = format_article(synopsis_article, config)
      expect(result["sections"]["Plot"]).to include("main character")
    end
  end

  describe "show_matched_sections option" do
    let(:wiki_with_synopsis) do
      <<~WIKI
        A movie summary.

        == Synopsis ==
        The story follows the main character.

        [[Category:Films]]
      WIKI
    end

    let(:synopsis_article) { Wp2txt::Article.new(wiki_with_synopsis, "Test Movie") }

    context "when enabled" do
      let(:config) do
        {
          format: :json,
          sections: ["summary", "Plot"],
          show_matched_sections: true,
          category: true
        }
      end

      it "includes matched_sections field" do
        result = format_article(synopsis_article, config)
        expect(result["matched_sections"]).to be_a(Hash)
        expect(result["matched_sections"]["Plot"]).to eq("Synopsis")
      end
    end

    context "when disabled (default)" do
      let(:config) do
        {
          format: :json,
          sections: ["summary", "Plot"],
          show_matched_sections: false,
          category: true
        }
      end

      it "does not include matched_sections field" do
        result = format_article(synopsis_article, config)
        expect(result).not_to have_key("matched_sections")
      end
    end

    context "with combined output mode" do
      let(:config) do
        {
          format: :json,
          sections: ["summary", "Plot"],
          section_output: "combined",
          show_matched_sections: true,
          category: true
        }
      end

      it "includes matched_sections in combined output" do
        result = format_article(synopsis_article, config)
        expect(result["matched_sections"]["Plot"]).to eq("Synopsis")
      end
    end
  end

  describe "no_section_aliases option" do
    let(:wiki_with_synopsis) do
      <<~WIKI
        A movie summary.

        == Synopsis ==
        The story follows the main character.

        [[Category:Films]]
      WIKI
    end

    let(:synopsis_article) { Wp2txt::Article.new(wiki_with_synopsis, "Test Movie") }

    context "when aliases are disabled" do
      let(:config) do
        {
          format: :json,
          sections: ["summary", "Plot"],
          no_section_aliases: true,
          category: true
        }
      end

      it "does not match Synopsis as Plot" do
        result = format_article(synopsis_article, config)
        expect(result["sections"]["Plot"]).to be_nil
      end
    end
  end

  describe "alias_file option" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:alias_file) { File.join(temp_dir, "custom_aliases.yml") }

    after { FileUtils.remove_entry(temp_dir) }

    let(:wiki_with_story) do
      <<~WIKI
        A summary.

        == Storyline ==
        The narrative unfolds.

        [[Category:Films]]
      WIKI
    end

    let(:story_article) { Wp2txt::Article.new(wiki_with_story, "Story Film") }

    before do
      File.write(alias_file, <<~YAML)
        Plot:
          - Storyline
          - Narrative
      YAML
    end

    let(:config) do
      {
        format: :json,
        sections: ["Plot"],
        alias_file: alias_file,
        category: true
      }
    end

    it "uses custom aliases from file" do
      result = format_article(story_article, config)
      expect(result["sections"]["Plot"]).to include("narrative unfolds")
    end
  end
end
