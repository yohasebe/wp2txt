# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require_relative "support/multistream_fixture"
require_relative "support/meta_db_fixture"
require_relative "../lib/wp2txt/corpus"
require_relative "../lib/wp2txt/corpus_jobs"
require_relative "../lib/wp2txt/output_path"

# extract_corpus titles: and query_sql output_path: (design doc 04)
RSpec.describe "titles extraction and SQL file output" do
  include MultistreamFixture
  include MetaDbFixture

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

      @corpus = Wp2txt::Corpus.for_input(@multistream_path, cache_dir: dir)
      example.run
      @corpus.close
    end
  end

  def read_jsonl(path)
    File.readlines(path).map { |l| JSON.parse(l) }
  end

  describe "extract_corpus titles:" do
    it "extracts an explicit set with normalization, dedup, and input order" do
      out = File.join(@dir, "t.jsonl")
      result = @corpus.extract_corpus(
        output_path: out, content: "summary",
        titles: ["Film B", "Film_A", "film A", "Film B"], num_processes: 0
      )

      expect(result[:total_matching]).to eq(2) # normalized + deduplicated
      expect(result[:articles_extracted]).to eq(2)
      expect(read_jsonl(out).map { |r| r["title"] }).to eq(["Film B", "Film A"])
      expect(result[:not_found][:count]).to eq(0)
    end

    it "resolves one redirect hop and extracts under the resolved title" do
      out = File.join(@dir, "t.jsonl")
      result = @corpus.extract_corpus(
        output_path: out, content: "summary", titles: ["Old Film"], num_processes: 0
      )

      expect(result[:articles_extracted]).to eq(1)
      expect(read_jsonl(out).first["title"]).to eq("Film A")
    end

    it "reports missing titles in not_found (count + sample)" do
      out = File.join(@dir, "t.jsonl")
      result = @corpus.extract_corpus(
        output_path: out, content: "summary",
        titles: ["Film A", "Ghost One", "Ghost Two"], num_processes: 0
      )

      expect(result[:articles_extracted]).to eq(1)
      expect(result[:not_found]).to eq({ count: 2, sample: ["Ghost One", "Ghost Two"] })
      meta = JSON.parse(File.read(result[:meta_path]))
      expect(meta["not_found"]["count"]).to eq(2)
    end

    it "counts a redirect whose target does not exist as not found" do
      db = SQLite3::Database.new(@db_path)
      db.execute("INSERT INTO pages (page_id, title, namespace, redirect_to, text_length) VALUES (99, 'Broken Redirect', 0, 'Nowhere', 0)")
      db.close

      out = File.join(@dir, "t.jsonl")
      result = @corpus.extract_corpus(
        output_path: out, content: "summary", titles: ["Broken Redirect"], num_processes: 0
      )
      expect(result[:not_found]).to eq({ count: 1, sample: ["Broken Redirect"] })
      expect(result[:articles_extracted]).to eq(0)
    end

    it "does not flag truncation for missing titles when the cap is not reached" do
      out = File.join(@dir, "t.jsonl")
      result = @corpus.extract_corpus(
        output_path: out, content: "summary",
        titles: ["Film A", "Ghost One", "Ghost Two"], num_processes: 0
      )

      expect(result[:not_found][:count]).to eq(2)
      expect(result[:articles_extracted]).to eq(1)
      expect(result[:truncated]).to be false
    end

    it "deduplicates titles that resolve to the same article" do
      db = SQLite3::Database.new(@db_path)
      db.execute("INSERT INTO pages (page_id, title, namespace, redirect_to, text_length) VALUES (98, 'Ancient Film', 0, 'Film A', 0)")
      db.close

      # (a) two aliases redirecting to the same target
      out1 = File.join(@dir, "t1.jsonl")
      result1 = @corpus.extract_corpus(
        output_path: out1, content: "summary",
        titles: ["Old Film", "Ancient Film"], num_processes: 0
      )
      expect(result1[:articles_extracted]).to eq(1)
      expect(read_jsonl(out1).map { |r| r["title"] }).to eq(["Film A"])

      # (b) a direct title plus its redirect alias
      out2 = File.join(@dir, "t2.jsonl")
      result2 = @corpus.extract_corpus(
        output_path: out2, content: "summary",
        titles: ["Film A", "Old Film"], num_processes: 0
      )
      expect(result2[:articles_extracted]).to eq(1)
      expect(read_jsonl(out2).map { |r| r["title"] }).to eq(["Film A"])
    end

    it "rejects combination with filter arguments (set is defined twice)" do
      out = File.join(@dir, "t.jsonl")
      [
        { category: "Japanese films" },
        { categories: ["Japanese films"] },
        { category_match: "films" },
        { title_match: "Film" }
      ].each do |filter|
        expect do
          @corpus.extract_corpus(output_path: out, content: "summary", titles: ["Film A"], **filter)
        end.to raise_error(ArgumentError, /query_sql/), "expected #{filter.keys.first} to conflict"
      end
    end

    it "rejects more than 10,000 titles" do
      expect do
        @corpus.extract_corpus(output_path: File.join(@dir, "t.jsonl"), content: "summary",
                               titles: Array.new(10_001) { |i| "T#{i}" })
      end.to raise_error(ArgumentError, /10_000|10000/)
    end

    it "interacts with limit and max_articles like the filter path" do
      titles = ["Film A", "Film B", "Person X"]
      limited = @corpus.extract_corpus(
        output_path: File.join(@dir, "t1.jsonl"), content: "summary",
        titles: titles, limit: 2, num_processes: 0
      )
      expect(limited[:articles_extracted]).to eq(2)
      expect(limited[:truncated]).to be true
      expect(limited[:total_matching]).to eq(3)

      capped = @corpus.extract_corpus(
        output_path: File.join(@dir, "t2.jsonl"), content: "summary",
        titles: titles, max_articles: 1, num_processes: 0
      )
      expect(capped[:articles_extracted]).to eq(1)
      expect(capped[:truncated]).to be true
    end

    it "enumerates titles in .meta.json when 100 or fewer, and the sha is order-independent" do
      result1 = @corpus.extract_corpus(
        output_path: File.join(@dir, "t1.jsonl"), content: "summary",
        titles: ["Film A", "Film B"], num_processes: 0
      )
      result2 = @corpus.extract_corpus(
        output_path: File.join(@dir, "t2.jsonl"), content: "summary",
        titles: ["Film B", "Film_A"], num_processes: 0
      )
      meta1 = JSON.parse(File.read(result1[:meta_path]))
      meta2 = JSON.parse(File.read(result2[:meta_path]))

      expect(meta1["query"]["titles"]).to eq(["Film A", "Film B"])
      expect(meta1["query"]["titles_count"]).to eq(2)
      expect(meta1["query"]["titles_sha256"]).to eq(meta2["query"]["titles_sha256"])
    end

    it "records only count + sha256 in .meta.json when more than 100 titles" do
      titles = ["Film A"] + Array.new(100) { |i| "Ghost #{i}" }
      result = @corpus.extract_corpus(
        output_path: File.join(@dir, "t.jsonl"), content: "summary",
        titles: titles, num_processes: 0
      )
      meta = JSON.parse(File.read(result[:meta_path]))

      expect(meta["query"]["titles_count"]).to eq(101)
      expect(meta["query"]["titles_sha256"]).to match(/\A[0-9a-f]{64}\z/)
      expect(meta["query"]).not_to have_key("titles")
    end

    it "passes titles through start_extract_job" do
      out = File.join(@dir, "job.jsonl")
      manager = Wp2txt::CorpusJobManager.new(
        -> { Wp2txt::Corpus.for_input(@multistream_path, cache_dir: @dir) }
      )
      start = manager.start_extract(
        output_path: out, content: "summary",
        titles: ["Film A", "Ghost"], num_processes: 0
      )

      deadline = Time.now + 30
      status = nil
      loop do
        status = manager.status(start[:job_id])
        break unless status[:status] == "running"
        raise "job did not finish in time" if Time.now > deadline

        sleep 0.1
      end

      expect(status[:status]).to eq("completed")
      expect(status[:result][:articles_extracted]).to eq(1)
      expect(status[:result][:not_found][:count]).to eq(1)
    end
  end

  describe "query_sql output_path:" do
    it "writes all rows as JSONL with NULLs and deduplicated column names" do
      out = File.join(@dir, "q.jsonl")
      result = @corpus.query_sql(
        "SELECT title, NULL AS note, page_id AS x, page_id AS x FROM pages " \
        "WHERE namespace = 0 AND redirect_to IS NULL ORDER BY page_id",
        output_path: out
      )

      expect(result[:columns]).to eq(["title", "note", "x", "x_2"])
      expect(result[:row_count]).to eq(3)
      expect(result[:sample].size).to eq(3)
      expect(result).not_to have_key(:rows)

      records = read_jsonl(out)
      expect(records.size).to eq(3)
      expect(records.first).to eq({ "title" => "Film A", "note" => nil, "x" => 1, "x_2" => 1 })
      expect(File.exist?("#{out}.partial")).to be false
    end

    it "ignores limit in file-output mode" do
      out = File.join(@dir, "q.jsonl")
      result = @corpus.query_sql("SELECT title FROM pages", output_path: out, limit: 1)
      expect(result[:row_count]).to eq(8)
      expect(read_jsonl(out).size).to eq(8)
    end

    it "refuses an existing output file unless overwrite is set" do
      out = File.join(@dir, "q.jsonl")
      File.write(out, "old")
      expect { @corpus.query_sql("SELECT 1", output_path: out) }
        .to raise_error(ArgumentError, /already exists/)
      expect(File.read(out)).to eq("old")

      @corpus.query_sql("SELECT 1 AS one", output_path: out, overwrite: true)
      expect(read_jsonl(out)).to eq([{ "one" => 1 }])
    end

    it "removes .partial and leaves no output on SQL error" do
      out = File.join(@dir, "q.jsonl")
      expect { @corpus.query_sql("SELECT * FROM no_such_table", output_path: out) }
        .to raise_error(ArgumentError, /SQL error/)
      expect(File.exist?(out)).to be false
      expect(File.exist?("#{out}.partial")).to be false
    end

    it "removes .partial and leaves no output on timeout kill" do
      out = File.join(@dir, "q.jsonl")
      runaway = "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c) SELECT x FROM c"
      expect { @corpus.query_sql(runaway, output_path: out, timeout: 1) }
        .to raise_error(ArgumentError, /time limit/)
      expect(File.exist?(out)).to be false
      expect(File.exist?("#{out}.partial")).to be false
    end

    it "truncates at SQL_FILE_ROW_LIMIT" do
      stub_const("Wp2txt::Corpus::SQL_FILE_ROW_LIMIT", 3)
      out = File.join(@dir, "q.jsonl")
      result = @corpus.query_sql("SELECT title FROM pages", output_path: out)

      expect(result[:row_count]).to eq(3)
      expect(result[:truncated]).to be true
      expect(read_jsonl(out).size).to eq(3)
    end

    it "clips cells over 64KB and counts them" do
      out = File.join(@dir, "q.jsonl")
      result = @corpus.query_sql(
        "SELECT printf('%.70000d', 0) AS big",
        output_path: out
      )

      expect(result[:cells_clipped]).to eq(1)
      value = read_jsonl(out).first["big"]
      expect(value.length).to eq(Wp2txt::Corpus::SQL_FILE_CELL_LIMIT + 1)
    end

    it "writes a .meta.json sidecar with SQL, attach provenance, and counts" do
      create_meta_db(@dir, lang: "en", date: "20260101",
                     pages: [[101, "Film A", 0, nil, 10]])
      out = File.join(@dir, "q.jsonl")
      result = @corpus.query_sql(
        "SELECT COUNT(*) AS n FROM en_meta.pages", attach: ["en"], output_path: out
      )

      expect(result[:attached].first[:lang]).to eq("en")
      meta = JSON.parse(File.read("#{out}.meta.json"))
      expect(meta["tool"]).to eq("query_sql")
      expect(meta["dump"]).to eq("testwiki-20260101")
      expect(meta["sql"]).to include("en_meta.pages")
      expect(meta["attached"]).to eq([
        { "lang" => "en", "dump_name" => "enwiki-20260101", "built_with" => Wp2txt::VERSION }
      ])
      expect(meta["row_count"]).to eq(1)
      expect(meta["truncated"]).to be false
      expect(meta["cells_clipped"]).to eq(0)
      expect(meta["generated_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(meta["wp2txt_version"]).to eq(Wp2txt::VERSION)
    end
  end

  describe Wp2txt::OutputPath do
    it "confines paths under the server output directory" do
      expect(described_class.confine("sub/out.jsonl", @dir)).to eq(File.join(@dir, "sub/out.jsonl"))
      expect { described_class.confine("../escape.jsonl", @dir) }
        .to raise_error(ArgumentError, /output directory/)
      expect { described_class.confine("/etc/passwd", @dir) }
        .to raise_error(ArgumentError, /output directory/)
    end

    it "refuses existing files unless overwrite is set" do
      existing = File.join(@dir, "exists.jsonl")
      File.write(existing, "x")
      expect { described_class.confine("exists.jsonl", @dir) }
        .to raise_error(ArgumentError, /already exists/)
      expect(described_class.confine("exists.jsonl", @dir, overwrite: true)).to eq(existing)
    end
  end
end
