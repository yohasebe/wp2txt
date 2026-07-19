# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/wp2txt/metadata_index"
require_relative "../lib/wp2txt/multistream"
require_relative "../lib/wp2txt/cli"

RSpec.describe "Wp2txt Metadata Index" do
  def page_xml(id:, ns:, title:, text:)
    escaped = text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    <<~XML
      <page>
        <title>#{title}</title>
        <ns>#{ns}</ns>
        <id>#{id}</id>
        <revision>
          <id>#{id * 100}</id>
          <text bytes="#{text.bytesize}">#{escaped}</text>
        </revision>
      </page>
    XML
  end

  def bzip2(data)
    out, status = Open3.capture2("bzip2", "-c", stdin_data: data)
    raise "bzip2 failed" unless status.success?

    out
  end

  # Two-stream multistream fixture:
  # stream 1 = articles (ns 0), stream 2 = category pages (ns 14)
  def create_fixture(dir)
    stream1_pages = [
      page_xml(id: 1, ns: 0, title: "Film A",
               text: "Intro.\n== Plot ==\nStory here.\n== Reception ==\nGood.\n[[Category:Japanese films]]\n"),
      page_xml(id: 2, ns: 0, title: "Film B",
               text: "Intro.\n== Synopsis ==\nStory here.\n[[Category:French films|B]]\n"),
      page_xml(id: 3, ns: 0, title: "Person X",
               text: "Bio.\n== Career ==\nActing.\n[[Category:Japanese actors]]\n"),
      page_xml(id: 4, ns: 0, title: "Old Film",
               text: "#REDIRECT [[Film A]]\n[[Category:Japanese films]]\n")
    ]
    stream2_pages = [
      page_xml(id: 5, ns: 14, title: "Category:Japanese films", text: "[[Category:Films]]\n"),
      page_xml(id: 6, ns: 14, title: "Category:French films", text: "[[Category:Films]]\n"),
      page_xml(id: 7, ns: 14, title: "Category:Films", text: "Top category.\n"),
      page_xml(id: 8, ns: 14, title: "Category:Japanese actors", text: "[[Category:People]]\n")
    ]

    stream1 = bzip2(stream1_pages.join)
    stream2 = bzip2(stream2_pages.join)

    multistream_path = File.join(dir, "testwiki-20260101-pages-articles-multistream.xml.bz2")
    File.binwrite(multistream_path, stream1 + stream2)

    offset2 = stream1.bytesize
    index_lines = [
      "0:1:Film A", "0:2:Film B", "0:3:Person X", "0:4:Old Film",
      "#{offset2}:5:Category:Japanese films", "#{offset2}:6:Category:French films",
      "#{offset2}:7:Category:Films", "#{offset2}:8:Category:Japanese actors"
    ]
    index_path = File.join(dir, "testwiki-20260101-pages-articles-multistream-index.txt")
    File.write(index_path, index_lines.join("\n") + "\n")

    [multistream_path, index_path]
  end

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
