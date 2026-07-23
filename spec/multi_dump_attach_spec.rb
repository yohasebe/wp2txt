# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "support/multistream_fixture"
require_relative "support/meta_db_fixture"
require_relative "../lib/wp2txt/corpus"
require_relative "../lib/wp2txt/langlinks_importer"

# query_sql's multi-dump ATTACH (design doc §2) and the langlinks join demo (§3)
RSpec.describe "multi-dump ATTACH" do
  include MultistreamFixture
  include MetaDbFixture

  EN_PAGES = [
    [101, "Film A", 0, nil, 100],
    [102, "Film B", 0, nil, 100],
    [103, "Person X (actor)", 0, nil, 100]
  ].freeze

  EN_SECTIONS = [
    [101, "Plot", 2, 1],
    [101, "Reception", 2, 2],
    [101, "Production", 2, 3],
    [102, "Synopsis", 2, 1]
  ].freeze

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      @multistream_path, @index_path = create_fixture(dir)

      ms_index = Wp2txt::MultistreamIndex.new(@index_path, use_cache: false, show_progress: false)
      @db_path = Wp2txt::MetadataIndex.path_for(@multistream_path, cache_dir: dir)
      Wp2txt::MetadataIndexBuilder.new(
        @multistream_path, ms_index.stream_offsets,
        db_path: @db_path, num_processes: 0
      ).build

      # Same-date "en" dump (attachable), different-date "fr" dump (mismatch)
      @en_meta = create_meta_db(dir, lang: "en", date: "20260101",
                                     pages: EN_PAGES, sections: EN_SECTIONS)
      @fr_meta = create_meta_db(dir, lang: "fr", date: "20260202",
                                     pages: [[201, "Film A (fr)", 0, nil, 50]])

      @corpus = Wp2txt::Corpus.for_input(@multistream_path, cache_dir: dir)
      example.run
      @corpus.close
    end
  end

  describe "attach argument validation" do
    it "rejects malformed language codes (paths, traversal, injection)" do
      ["../x", "en/x", "en;DROP", "EN", "e", "x" * 20, ""].each do |bad|
        expect { @corpus.query_sql("SELECT 1", attach: [bad]) }
          .to raise_error(ArgumentError, /invalid language code/), "expected #{bad.inspect} to be rejected"
      end
    end

    it "rejects languages with no installed index" do
      expect { @corpus.query_sql("SELECT 1", attach: ["ko"]) }
        .to raise_error(ArgumentError, /no installed index/)
    end

    it "rejects attaching the main database's own language" do
      expect { @corpus.query_sql("SELECT 1", attach: ["test"]) }
        .to raise_error(ArgumentError, /cannot attach 'test'/)
    end
  end

  describe "read-only cross-dump queries" do
    it "attaches another language's meta DB as {lang}_meta" do
      result = @corpus.query_sql("SELECT title FROM en_meta.pages ORDER BY page_id", attach: ["en"])
      expect(result[:rows].flatten).to eq(["Film A", "Film B", "Person X (actor)"])
    end

    it "attaches the FTS DB as {lang}_fts when built" do
      create_fts_db(@en_meta)
      result = @corpus.query_sql("SELECT name FROM en_fts.sqlite_master", attach: ["en"])
      expect(result[:rows].flatten).to include("fts_map")
      expect(result[:attached].first[:fts]).to be true
    end

    it "reports attached metadata (lang, dump_name, built_with, fts) in the response" do
      result = @corpus.query_sql("SELECT 1", attach: ["en"])
      expect(result[:attached]).to eq([
        { lang: "en", dump_name: "enwiki-20260101", built_with: Wp2txt::VERSION, fts: false }
      ])
    end

    it "flags dump_mismatch when only a different-date dump is installed" do
      result = @corpus.query_sql("SELECT 1", attach: ["fr"])
      entry = result[:attached].first
      expect(entry[:dump_name]).to eq("frwiki-20260202")
      expect(entry[:dump_mismatch]).to be true
    end

    it "makes attached databases read-only at the driver level" do
      attachments = @corpus.send(:resolve_attachments, ["en"])
      db = @corpus.send(:build_readonly_connection, attach_fts: false, attachments: attachments)
      expect { db.execute("INSERT INTO en_meta.pages VALUES (999, 'x', 0, NULL, 0)") }
        .to raise_error(SQLite3::Exception, /readonly/i)
      db.close
    end

    it "maps hyphenated language codes to underscored aliases (zh-yue → zh_yue_meta)" do
      create_meta_db(@dir, lang: "zh-yue", date: "20260101",
                     pages: [[301, "Cantonese Page", 0, nil, 10]])
      result = @corpus.query_sql("SELECT title FROM zh_yue_meta.pages", attach: ["zh-yue"])
      expect(result[:rows].flatten).to eq(["Cantonese Page"])
      expect(result[:attached].first[:lang]).to eq("zh-yue")
    end
  end

  describe "user SQL ATTACH/DETACH stays forbidden (regression)" do
    it "rejects ATTACH in user SQL even when the attach argument is used" do
      expect { @corpus.query_sql("SELECT 1; ATTACH DATABASE 'x' AS y", attach: ["en"]) }
        .to raise_error(ArgumentError, /forbidden/)
    end

    it "rejects DETACH in user SQL" do
      expect { @corpus.query_sql("SELECT 1; DETACH DATABASE en_meta", attach: ["en"]) }
        .to raise_error(ArgumentError, /forbidden/)
    end

    it "still allows 'attach' inside string literals" do
      result = @corpus.query_sql("SELECT 'please attach the file' AS note")
      expect(result[:rows].first.first).to eq("please attach the file")
    end
  end

  describe "langlinks join demo (design doc §3)" do
    before do
      path = File.join(@dir, "testwiki-20260101-langlinks.sql")
      File.write(path, <<~SQL)
        INSERT INTO `langlinks` VALUES (1,'en','Film A'),(2,'en','Film B'),(3,'en','Person X (actor)');
      SQL
      Wp2txt::LanglinksImporter.new(@db_path, cache_dir: @dir).import!(path)
    end

    it "compares section structures of article pairs across languages in one query" do
      result = @corpus.query_sql(<<~SQL, attach: ["en"])
        SELECT p.title AS ja_title, ll.ll_title AS en_title,
               (SELECT COUNT(*) FROM page_sections s WHERE s.page_id = p.page_id) AS ja_sections,
               (SELECT COUNT(*) FROM en_meta.page_sections s2
                JOIN en_meta.pages p2 ON p2.page_id = s2.page_id
                WHERE p2.title = ll.ll_title) AS en_sections
        FROM pages p
        JOIN langlinks ll ON ll.ll_from = p.page_id AND ll.ll_lang = 'en'
        WHERE p.namespace = 0 AND p.redirect_to IS NULL
        LIMIT 20
      SQL

      expect(result[:columns]).to eq(%w[ja_title en_title ja_sections en_sections])
      expect(result[:rows]).to contain_exactly(
        ["Film A", "Film A", 2, 3],
        ["Film B", "Film B", 1, 1],
        ["Person X", "Person X (actor)", 2, 0]
      )
    end

    it "exposes langlinks provenance via dump_info" do
      info = @corpus.dump_info
      expect(info[:langlinks][:source]).to eq("testwiki-20260101-langlinks.sql")
      expect(info[:langlinks][:row_count]).to eq(3)
    end

    it "includes the langlinks table in describe_schema (introspection-based)" do
      schemas = @corpus.describe_schema[:meta].join("\n")
      expect(schemas).to include("CREATE TABLE langlinks")
      expect(schemas).to include("idx_langlinks_from")
    end
  end
end
