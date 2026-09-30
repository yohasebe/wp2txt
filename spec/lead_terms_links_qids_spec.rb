# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "zlib"
require_relative "support/multistream_fixture"
require "wp2txt"
require "wp2txt/metadata_index"
require "wp2txt/multistream"
require "wp2txt/sql_dump_reader"
require "wp2txt/page_props_importer"
require "wp2txt/link_counter"
require "wp2txt/lead_terms"

RSpec.describe "lead terms, incoming links, and Wikidata IDs" do
  include MultistreamFixture

  around do |example|
    Dir.mktmpdir("wp2txt-ltq-") do |dir|
      @dir = dir
      example.run
    end
  end

  def xml_page(id:, title:, text:, ns: 0)
    esc = ->(s) { s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;") }
    "<page>\n<title>#{esc.(title)}</title>\n<ns>#{ns}</ns>\n<id>#{id}</id>\n<revision>\n<id>#{id * 100}</id>\n" \
      "<text bytes=\"#{text.bytesize}\">#{esc.(text)}</text>\n</revision>\n</page>\n"
  end

  PAGES = [
    [1, "東京", "'''東京'''（とうきょう、Tokyo）は首都。\n\n== 歴史 ==\n'''後'''（あと）", 0],
    [2, "東京都区部", "#REDIRECT [[東京]]", 0],
    [3, "記事A", "[[東京]]と[[東京]]、[[東京都区部]]。[[M&A|買収]]。<!-- [[隠れ]] -->[[#節]][[]]", 0],
    [4, "記事B", "[[東京#歴史|東京の歴史]]", 0],
    [5, "記事C", "[[東京都区部]]のみ。", 0],
    [6, "M&A", "'''{{読み仮名|合併|がっぺい}}'''と買収。", 0],
    [7, "隠れ", "", 0],
    [8, "Category:X", "[[東京]]", 14]
  ].freeze

  # One-stream dump with its index and a built metadata index
  def build_dump
    dump = File.join(@dir, "testwiki-20260101-pages-articles-multistream.xml.bz2")
    File.binwrite(dump, bzip2(PAGES.map { |id, t, x, ns| xml_page(id: id, title: t, text: x, ns: ns) }.join))
    File.write(File.join(@dir, "testwiki-20260101-pages-articles-multistream-index.txt"),
               PAGES.map { |id, t, _, _| "0:#{id}:#{t}" }.join("\n") + "\n")
    db = Wp2txt::MetadataIndex.path_for(dump, cache_dir: @dir)
    Wp2txt::MetadataIndexBuilder.new(dump, [0], db_path: db, num_processes: 0).build.close
    [dump, db]
  end

  def page_props_file(content, name: "testwiki-20260101-page_props.sql.gz")
    path = File.join(@dir, name)
    Zlib::GzipWriter.open(path) { |gz| gz.write(content) }
    path
  end

  PAGE_PROPS_SQL = <<~SQL
    INSERT INTO `page_props` VALUES
    (1,'wikibase_item','Q1490',NULL),
    (1,'page_image_free','T\\'kyo.jpg',NULL),
    (3,'wikibase_item','Q9',1.5),
    (6,'wikibase_item','Q1\\'bad',NULL),
    (6,'defaultsort','\xFF\xFE',NULL);
    INSERT INTO `page_restrictions` VALUES
    (1,'wikibase_item','Q777',NULL);
  SQL

  describe Wp2txt::SqlDumpReader do
    it "reads statements written on one line and one tuple per line, skipping other tables" do
      lines = []
      path = page_props_file("INSERT INTO `t` VALUES (1),(2);\nINSERT INTO `u` VALUES\n(9);\nINSERT INTO `t` VALUES\n(3),\n(4);\n")
      described_class.each_insert_line(path, "t") { |l| lines << l.strip }
      expect(lines).to eq(["INSERT INTO `t` VALUES (1),(2);", "INSERT INTO `t` VALUES", "(3),", "(4);"])
    end
  end

  describe Wp2txt::PagePropsImporter do
    it "imports only well-formed wikibase_item values, and records where they came from" do
      _dump, db = build_dump
      path = page_props_file(PAGE_PROPS_SQL.b)
      result = described_class.new(db).import!(path)
      expect(result[:row_count]).to eq(2)
      rows = SQLite3::Database.new(db, readonly: true).execute("SELECT page_id, qid FROM page_qids ORDER BY page_id")
      expect(rows).to eq([[1, "Q1490"], [3, "Q9"]])
      expect(result[:provenance][:source_sha256]).to eq(Digest::SHA256.file(path).hexdigest)
      expect(described_class.new(db).import!(path)[:status]).to eq(:already_imported)
    end

    it "refuses a dump of another date" do
      _dump, db = build_dump
      path = page_props_file(PAGE_PROPS_SQL.b, name: "testwiki-20250101-page_props.sql.gz")
      expect { described_class.new(db).import!(path) }.to raise_error(ArgumentError, /version mismatch/)
    end

    it "fails when nothing could be read" do
      _dump, db = build_dump
      path = page_props_file("-- empty\n")
      expect { described_class.new(db).import!(path) }.to raise_error(Wp2txt::Error, /no page_props rows/)
    end
  end

  describe Wp2txt::LinkCounter do
    it "counts each linking article once, through redirects, ignoring comments and non-articles" do
      dump, db = build_dump
      described_class.new(dump, [0], db_path: db, num_processes: 0).count!
      counts = SQLite3::Database.new(db, readonly: true)
                                .execute("SELECT p.title, i.inlinks, i.via_redirects FROM page_inlinks i " \
                                         "JOIN pages p USING (page_id)").to_h { |t, n, v| [t, [n, v]] }
      expect(counts["東京"]).to eq([3, 1]) # 記事A and 記事B directly, 記事C only via the redirect
      expect(counts["M&A"]).to eq([1, 0])
      expect(counts["隠れ"]).to eq([0, 0]) # linked only from a comment
      expect(counts["記事A"]).to eq([0, 0])
      expect(counts).not_to have_key("東京都区部") # redirects get no row of their own
    end
  end

  describe Wp2txt::LeadTerms do
    let(:render) { ->(fragment) { Object.new.extend(Wp2txt).format_wiki(fragment, { expand_templates: true, markers: [:all] }) } }

    def terms(text)
      Wp2txt::LeadTerms.extract(text, render: render)
    end

    it "takes bold terms of the first paragraph that has one, skipping templates, files, refs, and comments" do
      text = "{{Otheruses|'''x'''}}\n[[ファイル:A.jpg|thumb|'''偽''']]<!-- '''隠''' --><ref>'''注'''</ref>\n" \
             "'''日本語'''（にほんご、にっぽんご{{Refnest|注}}）は言語。'''和語'''とも。\n\n次の段落の'''別'''。"
      expect(terms(text).map { |t| [t["text"], t["notes"]] }).to eq([["日本語", %w[にほんご にっぽんご]], ["和語", []]])
    end

    it "reports spans that cut the bold and the parentheses out of the original text" do
      text = "前置き。'''東京'''　（とうきょう）は首都。"
      term = terms(text).first
      expect(text[Range.new(*term["span"]["bold"], true)]).to eq("'''東京'''")
      expect(text[Range.new(*term["span"]["paren"], true)]).to eq("（とうきょう）")
      expect(term["notes_text"]).to eq("とうきょう")
    end

    it "does not split inside nested brackets, templates, or links" do
      text = "'''井上陽水'''（いのうえ ようすい、[[1948年]]（昭和23年、戊子）[[8月30日]] - 、{{lang|en|a, b}}）は歌手。"
      expect(terms(text).first["notes"]).to eq(["いのうえ ようすい", "1948年（昭和23年、戊子）8月30日 -", "a, b"])
    end

    it "reports reading templates as pairs and keeps their reading out of the bold text" do
      result = terms("'''{{読み仮名|言語|げんご}}'''は記号体系。")
      expect(result.map { |t| t.slice("text", "reading", "source") })
        .to eq([{ "text" => "言語", "source" => "bold" },
                { "text" => "言語", "reading" => "げんご", "source" => "読み仮名" }])
    end

    it "stops at the first heading, ignores an unclosed bracket, and caps the count" do
      expect(terms("'''甲'''（こう\n\n== 節 ==\n'''乙'''").map { |t| [t["text"], t["notes"]] }).to eq([["甲", []]])
      many = (1..8).map { |i| "'''語#{i}'''" }.join("、")
      expect(terms(many).map { |t| t["index"] }).to eq([0, 1, 2, 3, 4])
    end

    it "returns nothing for empty text" do
      expect(terms("")).to eq([])
    end
  end

  describe "command line" do
    let(:cli) { File.expand_path("../bin/wp2txt", __dir__) }
    let(:lib) { File.expand_path("../lib", __dir__) }

    def records(*args)
      out = File.join(@dir, "out#{args.hash.abs}")
      Dir.mkdir(out)
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", lib, cli, *args, "-o", out)
      expect(status.success?).to be(true), stderr
      Dir[File.join(out, "*")].flat_map { |f| File.readlines(f) }.map { |l| JSON.parse(l) }.to_h { |r| [r["title"], r] }
    end

    it "adds the Wikidata ID and lead terms to JSON, identically on both extraction paths" do
      dump, db = build_dump
      Wp2txt::PagePropsImporter.new(db).import!(page_props_file(PAGE_PROPS_SQL.b))
      common = ["-i", dump, "--cache-dir", @dir, "--format", "json", "--summary-only", "--lead-terms"]
      turbo = records(*common)
      streamed = records(*common, "--no-turbo")

      expect(turbo["東京"].keys.first(4)).to eq(%w[title page_id revision_id qid])
      expect(turbo["東京"]["qid"]).to eq("Q1490")
      expect(turbo["記事B"]).not_to have_key("qid")
      expect(turbo["東京"]["lead_terms"].first.slice("text", "notes"))
        .to eq("text" => "東京", "notes" => %w[とうきょう Tokyo])
      # (the default path skips articles with empty text; compare what both emit)
      common_titles = turbo.keys & streamed.keys
      expect(common_titles.size).to eq(turbo.size)
      expect(streamed.slice(*common_titles).transform_values { |r| r["lead_terms"] })
        .to eq(turbo.transform_values { |r| r["lead_terms"] })
    end

    it "requires JSON output for --lead-terms" do
      input = File.join(@dir, "x.xml.bz2")
      File.write(input, "")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", lib, cli, "-i", input, "--lead-terms")
      expect(status.success?).to be(false)
      expect(stderr).to include("--lead-terms requires --format json")
    end
  end
end
