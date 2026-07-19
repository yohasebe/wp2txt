# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "support/multistream_fixture"
require_relative "../lib/wp2txt/metadata_index"
require_relative "../lib/wp2txt/multistream"
require_relative "../lib/wp2txt/cli"

RSpec.describe "Wp2txt Metadata Index" do
  include MultistreamFixture

  describe Wp2txt::MetadataIndex do
    describe ".normalize_category" do
      it "replaces underscores, trims, and capitalizes the first letter" do
        expect(described_class.normalize_category(" japanese_films ")).to eq("Japanese films")
      end

      it "leaves non-ASCII names unchanged" do
        expect(described_class.normalize_category("日本の映画作品")).to eq("日本の映画作品")
      end
    end

    describe ".clean_heading" do
      it "strips bold markup and resolves links" do
        expect(described_class.clean_heading("'''Bold''' [[link|Label]]")).to eq("Bold Label")
      end

      it "strips HTML tags" do
        expect(described_class.clean_heading("<small>Notes</small>")).to eq("Notes")
      end
    end

    describe ".expand_section_names" do
      it "expands a canonical name to its alias group" do
        expect(described_class.expand_section_names("Plot")).to include("Plot", "Synopsis")
      end

      it "expands an alias back to the full group (bidirectional)" do
        expect(described_class.expand_section_names("Synopsis")).to include("Plot", "Synopsis")
      end

      it "returns the name itself when no alias group matches" do
        expect(described_class.expand_section_names("Nonexistent Section")).to eq(["Nonexistent Section"])
      end
    end

    describe ".path_for" do
      it "builds a cache path keyed to the dump file" do
        path = described_class.path_for("/dumps/jawiki-20260101-pages-articles-multistream.xml.bz2", cache_dir: "/cache")
        expect(path).to start_with("/cache/jawiki-20260101-pages-articles-multistream")
        expect(path).to end_with("_meta.sqlite3")
      end
    end
  end

  describe "build and query" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        @multistream_path, @index_path = create_fixture(dir)
        @db_path = File.join(dir, "meta.sqlite3")
        ms_index = Wp2txt::MultistreamIndex.new(@index_path, use_cache: false, show_progress: false)
        builder = Wp2txt::MetadataIndexBuilder.new(
          @multistream_path, ms_index.stream_offsets,
          db_path: @db_path, num_processes: 0
        )
        @index = builder.build
        example.run
        @index.close
      end
    end

    it "records all pages and counts articles excluding redirects and category pages" do
      stats = @index.stats
      expect(stats[:page_count]).to eq(8)
      expect(stats[:article_count]).to eq(3)
      expect(stats[:dump_name]).to eq("testwiki-20260101")
    end

    it "finds articles by exact category" do
      expect(@index.find_articles(category: "Japanese films")).to eq(["Film A"])
    end

    it "finds articles through subcategories with depth" do
      expect(@index.find_articles(category: "Films", depth: 1)).to contain_exactly("Film A", "Film B")
    end

    it "does not include subcategory members at depth 0" do
      expect(@index.find_articles(category: "Films", depth: 0)).to be_empty
    end

    it "matches sections through aliases" do
      titles = @index.find_articles(category: "Films", depth: 1, has_section: "Plot")
      expect(titles).to contain_exactly("Film A", "Film B")
    end

    it "matches sections exactly when aliases are disabled" do
      titles = @index.find_articles(category: "Films", depth: 1, has_section: "Plot", use_aliases: false)
      expect(titles).to eq(["Film A"])
    end

    it "excludes redirects from results" do
      expect(@index.find_articles(title_match: "Old Film")).to be_empty
    end

    it "filters by title substring" do
      expect(@index.find_articles(title_match: "Film")).to contain_exactly("Film A", "Film B")
    end

    it "applies limit and reports full count separately" do
      titles = @index.find_articles(title_match: "Film", limit: 1)
      expect(titles.size).to eq(1)
      expect(@index.count_articles(title_match: "Film")).to eq(2)
    end

    it "returns the category tree with depths" do
      tree = @index.category_tree("Films", depth: 1)
      expect(tree).to include({ name: "Films", depth: 0 },
                              { name: "Japanese films", depth: 1 },
                              { name: "French films", depth: 1 })
    end

    it "collects section statistics" do
      stats = @index.section_stats
      expect(stats).to include(["Plot", 1], ["Synopsis", 1], ["Career", 1])
    end

    it "scopes section statistics to a category" do
      stats = @index.section_stats(category: "Films", depth: 1)
      headings = stats.map(&:first)
      expect(headings).to include("Plot", "Synopsis")
      expect(headings).not_to include("Career")
    end

    it "records redirect targets" do
      db = SQLite3::Database.new(@db_path)
      target = db.get_first_value("SELECT redirect_to FROM pages WHERE title = 'Old Film'")
      db.close
      expect(target).to eq("Film A")
    end

    it "validates against the source dump file" do
      expect(@index.built?).to be true
      expect(@index.valid_for?(@multistream_path)).to be true
    end

    it "detects a changed source dump file" do
      File.binwrite(@multistream_path, File.binread(@multistream_path) + "x")
      expect(@index.valid_for?(@multistream_path)).to be false
    end

    it "reports not built for a missing index file" do
      missing = Wp2txt::MetadataIndex.new(File.join(@dir, "nope.sqlite3"))
      expect(missing.built?).to be false
    end
  end

  describe "CLI option validation" do
    it "rejects --in-category without --find-articles" do
      expect do
        Wp2txt::CLI.parse_options(["-L", "ja", "--in-category", "Films"])
      end.to raise_error(SystemExit)
    end

    it "rejects combining --build-index with --find-articles" do
      expect do
        Wp2txt::CLI.parse_options(["-L", "ja", "--build-index", "--find-articles"])
      end.to raise_error(SystemExit)
    end

    it "accepts --find-articles with filters" do
      opts = Wp2txt::CLI.parse_options(["-L", "ja", "--find-articles", "--in-category", "Films", "--has-section", "Plot"])
      expect(opts[:find_articles]).to be true
      expect(opts[:in_category]).to eq("Films")
      expect(opts[:has_section]).to eq("Plot")
    end
  end
end
