# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require_relative "support/multistream_fixture"
require_relative "../lib/wp2txt/fts_index"
require_relative "../lib/wp2txt/corpus"

RSpec.describe "Wp2txt Full-Text Search" do
  include MultistreamFixture

  def build_indexes(dir, tokenizer: "unicode61", optimize: true)
    multistream_path, index_path = create_fixture(dir)
    ms_index = Wp2txt::MultistreamIndex.new(index_path, use_cache: false, show_progress: false)

    meta_db = Wp2txt::MetadataIndex.path_for(multistream_path, cache_dir: dir)
    Wp2txt::MetadataIndexBuilder.new(
      multistream_path, ms_index.stream_offsets, db_path: meta_db, num_processes: 0
    ).build

    fts_db = Wp2txt::FtsIndex.path_for(multistream_path, cache_dir: dir)
    Wp2txt::FtsIndexBuilder.new(
      multistream_path, ms_index.stream_offsets,
      db_path: fts_db, meta_db_path: meta_db, tokenizer: tokenizer,
      num_processes: 0, optimize: optimize
    ).build

    [multistream_path, fts_db, meta_db]
  end

  describe Wp2txt::FtsIndex do
    describe ".default_tokenizer" do
      it "picks trigram for CJK language dumps" do
        expect(described_class.default_tokenizer("/x/jawiki-20260701-multistream.xml.bz2")).to eq("trigram")
        expect(described_class.default_tokenizer("/x/zhwiki-20260701-multistream.xml.bz2")).to eq("trigram")
      end

      it "picks unicode61 for space-delimited language dumps" do
        expect(described_class.default_tokenizer("/x/enwiki-20260701-multistream.xml.bz2")).to eq("unicode61")
        expect(described_class.default_tokenizer("/x/dewiki-20260701-multistream.xml.bz2")).to eq("unicode61")
      end
    end

    context "with a built unicode61 index" do
      around do |example|
        Dir.mktmpdir do |dir|
          @multistream_path, fts_db, meta_db = build_indexes(dir)
          @fts = described_class.new(fts_db, meta_db)
          example.run
          @fts.close
        end
      end

      it "is built, valid, and records the tokenizer" do
        expect(@fts.built?).to be true
        expect(@fts.valid_for?(@multistream_path)).to be true
        expect(@fts.tokenizer).to eq("unicode61")
        expect(@fts.stats[:section_count]).to be > 0
      end

      it "finds matches across articles with exact counts" do
        result = @fts.search("Story", count: "exact")
        expect(result[:total]).to eq(2)
        expect(result[:total_is_capped]).to be false
        expect(result[:hits].map { |h| h[:title] }).to contain_exactly("Film A", "Film B")
      end

      it "searches lead sections (empty heading)" do
        result = @fts.search("Intro", count: "exact")
        expect(result[:total]).to eq(2)
        expect(result[:hits].map { |h| h[:heading] }.uniq).to eq([""])
      end

      it "excludes redirect pages from the index" do
        result = @fts.search("Old Film", count: "exact")
        expect(result[:total]).to eq(0)
      end

      it "returns zero for absent strings (absence claim)" do
        expect(@fts.search("zebra unicorn", count: "exact")[:total]).to eq(0)
      end

      it "composes with an exact category filter" do
        result = @fts.search("Story", category: "Japanese films", count: "exact")
        expect(result[:hits].map { |h| h[:title] }).to eq(["Film A"])
      end

      it "composes with a recursive category filter" do
        result = @fts.search("Story", category: "Films", depth: 1, count: "exact")
        expect(result[:total]).to eq(2)
      end

      it "composes with a section filter" do
        result = @fts.search("Story", sections: ["Plot"], count: "exact")
        expect(result[:hits].map { |h| h[:heading] }).to eq(["Plot"])
      end

      it "normalizes decorated headings the same way as the metadata index" do
        result = @fts.search("Distinct prose", count: "exact")
        expect(result[:hits].map { |h| h[:heading] }).to eq(["Style"])
        expect(@fts.search("Distinct prose", sections: ["Style"], count: "exact")[:total]).to eq(1)
      end

      it "keeps ord aligned between page_sections and fts_map (shared semantics)" do
        meta_db = SQLite3::Database.new(@fts.meta_db_path, readonly: true)
        meta_ord = meta_db.get_first_value(
          "SELECT ps.ord FROM page_sections ps JOIN pages p ON p.page_id = ps.page_id " \
          "WHERE p.title = 'Person X' AND ps.heading = 'Career'"
        )
        meta_db.close
        fts_db = SQLite3::Database.new(@fts.db_path, readonly: true)
        fts_ord = fts_db.get_first_value(
          "SELECT fm.ord FROM fts_map fm WHERE fm.heading = 'Career'"
        )
        fts_db.close
        expect(meta_ord).to eq(1) # lead = 0 (not stored), first heading = 1
        expect(fts_ord).to eq(meta_ord)
      end

      it "caps counting when requested" do
        result = @fts.search("Story", count: "capped", count_cap: 1)
        expect(result[:total]).to eq(1)
        expect(result[:total_is_capped]).to be true
      end

      it "supports raw FTS5 query mode" do
        result = @fts.search("Story OR Acting", mode: "query", count: "exact")
        expect(result[:total]).to eq(3)
      end

      it "escapes quotes in phrase mode" do
        expect { @fts.search('say "hi" now', count: "exact") }.not_to raise_error
      end
    end

    context "built with optimize: false" do
      around do |example|
        Dir.mktmpdir do |dir|
          @multistream_path, fts_db, meta_db = build_indexes(dir, optimize: false)
          @fts = described_class.new(fts_db, meta_db)
          example.run
          @fts.close
        end
      end

      it "is valid, flagged unoptimized, and fully searchable" do
        expect(@fts.built?).to be true
        expect(@fts.valid_for?(@multistream_path)).to be true
        expect(@fts.optimized?).to be false
        expect(@fts.stats[:optimized]).to be false
        expect(@fts.search("Story", count: "exact")[:total]).to eq(2)
      end

      it "can be optimized afterwards (idempotent)" do
        expect(@fts.optimize!).to be true
        expect(@fts.optimized?).to be true
        expect(@fts.search("Story", count: "exact")[:total]).to eq(2)
        expect(@fts.optimize!).to be true
      end
    end

    context "with a trigram index" do
      around do |example|
        Dir.mktmpdir do |dir|
          @multistream_path, fts_db, meta_db = build_indexes(dir, tokenizer: "trigram")
          @fts = described_class.new(fts_db, meta_db)
          example.run
          @fts.close
        end
      end

      it "matches substrings of three or more characters" do
        result = @fts.search("tory", count: "exact")
        expect(result[:total]).to eq(2)
      end
    end
  end

  describe "Corpus#search_text" do
    around do |example|
      Dir.mktmpdir do |dir|
        @multistream_path, = build_indexes(dir)
        @corpus = Wp2txt::Corpus.for_input(@multistream_path, cache_dir: dir)
        example.run
        @corpus.close
      end
    end

    it "reports the fulltext tier in dump_info" do
      info = @corpus.dump_info
      expect(info[:tiers][:fulltext]).to be true
      expect(info[:fulltext_current]).to be true
      expect(info[:fulltext][:tokenizer]).to eq("unicode61")
    end

    it "exposes the fts tables to query_sql" do
      result = @corpus.query_sql("SELECT COUNT(*) FROM fts.fts_map")
      expect(result[:rows].first.first).to be > 0
      expect(@corpus.describe_schema[:fts].join).to include("fts_map")
    end

    it "returns hits with section paths and dump identity" do
      result = @corpus.search_text("Story", count: "exact")
      expect(result[:dump]).to eq("testwiki-20260101")
      expect(result[:total]).to eq(2)
      paths = result[:hits].map { |h| h[:section_path] }
      expect(paths).to contain_exactly("Film A > Plot", "Film B > Synopsis")
    end

    it "renders snippets containing the search term" do
      result = @corpus.search_text("Story")
      expect(result[:hits].first[:snippet]).to include("Story")
    end

    it "uses the article title as section_path for lead hits" do
      result = @corpus.search_text("Intro", count: "exact")
      expect(result[:hits].map { |h| h[:section_path] }).to contain_exactly("Film A", "Film B")
      expect(result[:hits].first).not_to have_key(:section)
    end

    it "expands section filters through alias sets" do
      @corpus.save_alias_set("plot", [%w[Plot Synopsis]], min_articles: 1)
      result = @corpus.search_text("Story", sections: ["Plot"], alias_set: "plot", count: "exact")
      expect(result[:total]).to eq(2)
    end

    it "raises a helpful error when the index is missing" do
      Dir.mktmpdir do |dir2|
        ms2, = create_fixture(dir2)
        ms_index = Wp2txt::MultistreamIndex.new(
          ms2.sub(/multistream\.xml\.bz2\z/, "multistream-index.txt"), use_cache: false, show_progress: false
        )
        Wp2txt::MetadataIndexBuilder.new(
          ms2, ms_index.stream_offsets,
          db_path: Wp2txt::MetadataIndex.path_for(ms2, cache_dir: dir2), num_processes: 0
        ).build
        corpus2 = Wp2txt::Corpus.for_input(ms2, cache_dir: dir2)
        expect { corpus2.search_text("x") }.to raise_error(ArgumentError, /Full-text index not built/)
        corpus2.close
      end
    end
  end
end
