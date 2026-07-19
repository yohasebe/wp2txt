# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require_relative "support/multistream_fixture"
require_relative "../lib/wp2txt/corpus"
require_relative "../lib/wp2txt/corpus_jobs"

RSpec.describe Wp2txt::Corpus do
  include MultistreamFixture

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      @multistream_path, @index_path = create_fixture(dir)

      ms_index = Wp2txt::MultistreamIndex.new(@index_path, use_cache: false, show_progress: false)
      db_path = Wp2txt::MetadataIndex.path_for(@multistream_path, cache_dir: dir)
      Wp2txt::MetadataIndexBuilder.new(
        @multistream_path, ms_index.stream_offsets,
        db_path: db_path, num_processes: 0
      ).build

      @corpus = described_class.for_input(@multistream_path, cache_dir: dir)
      example.run
      @corpus.close
    end
  end

  describe ".for_input" do
    it "locates the index file next to the dump" do
      expect(@corpus.index_path).to eq(@index_path)
    end

    it "raises when no index file exists" do
      orphan = File.join(@dir, "orphan-multistream.xml.bz2")
      FileUtils.cp(@multistream_path, orphan)
      expect { described_class.for_input(orphan, cache_dir: @dir) }.to raise_error(ArgumentError, /index file not found/)
    end
  end

  describe "#dump_info" do
    it "reports dump identity, tiers, and stats" do
      info = @corpus.dump_info
      expect(info[:dump]).to eq("testwiki-20260101")
      expect(info[:tiers]).to eq({ titles: true, metadata: true, fulltext: false })
      expect(info[:metadata_current]).to be true
      expect(info[:stats][:article_count]).to eq(3)
    end
  end

  describe "#get_article" do
    it "returns cleaned text by default" do
      result = @corpus.get_article("Film A")
      expect(result[:id]).to eq(1)
      expect(result[:text]).to include("Story here")
      expect(result[:text]).not_to include("[[Category:")
    end

    it "returns raw wikitext when requested" do
      result = @corpus.get_article("Film A", format: "wikitext")
      expect(result[:text]).to include("[[Category:Japanese films]]")
    end

    it "resolves one redirect hop" do
      result = @corpus.get_article("Old Film")
      expect(result[:title]).to eq("Film A")
    end

    it "returns nil for a missing title" do
      expect(@corpus.get_article("Nope")).to be_nil
    end
  end

  describe "#get_sections" do
    it "extracts the requested section content" do
      result = @corpus.get_sections("Film A", ["Plot"])
      expect(result[:sections]["Plot"]).to include("Story here")
    end

    it "expands names through a saved alias set" do
      @corpus.save_alias_set("test-plot", [%w[Plot Synopsis]])
      result = @corpus.get_sections("Film B", ["Plot"], alias_set: "test-plot")
      expect(result[:resolved]).to contain_exactly("Plot", "Synopsis")
      expect(result[:sections].values.compact.join).to include("Story here")
    end
  end

  describe "#list_headings" do
    it "lists headings with levels" do
      result = @corpus.list_headings("Film A")
      expect(result[:headings]).to eq([
        { name: "Plot", level: 2 },
        { name: "Reception", level: 2 }
      ])
    end
  end

  describe "#find_articles" do
    it "matches any of multiple section headings (array primitive)" do
      result = @corpus.find_articles(sections: %w[Plot Synopsis])
      expect(result[:total]).to eq(2)
      expect(result[:titles]).to contain_exactly("Film A", "Film B")
    end

    it "expands sections through a saved alias set" do
      @corpus.save_alias_set("test-plot", [%w[Plot Synopsis]])
      result = @corpus.find_articles(sections: ["Plot"], alias_set: "test-plot")
      expect(result[:titles]).to contain_exactly("Film A", "Film B")
    end

    it "includes the dump identifier for provenance" do
      expect(@corpus.find_articles(title_match: "Film")[:dump]).to eq("testwiki-20260101")
    end
  end

  describe "#section_cooccurrence" do
    it "reports zero co-occurrence for headings that never share an article" do
      result = @corpus.section_cooccurrence(%w[Plot Synopsis])
      pair = result[:pairs].first
      expect(pair[:both]).to eq(0)
      expect(pair[:cooccurrence_ratio]).to eq(0.0)
    end

    it "reports co-occurrence for headings in the same article" do
      result = @corpus.section_cooccurrence(%w[Plot Reception])
      pair = result[:pairs].first
      expect(pair[:both]).to eq(1)
      expect(pair[:cooccurrence_ratio]).to eq(1.0)
    end

    it "includes per-heading article counts and positions" do
      result = @corpus.section_cooccurrence(%w[Plot Reception])
      plot = result[:headings].find { |h| h[:heading] == "Plot" }
      expect(plot[:articles]).to eq(1)
      expect(plot[:avg_position]).to eq(0.0)
    end

    it "scopes to an exact category" do
      result = @corpus.section_cooccurrence(%w[Plot Reception], category: "Japanese films")
      expect(result[:headings].map { |h| h[:articles] }).to eq([1, 1])
      expect(result[:pairs].first[:both]).to eq(1)
    end

    it "scopes to a recursive category (CTE placeholder ordering regression)" do
      result = @corpus.section_cooccurrence(%w[Plot Synopsis], category: "Films", depth: 1)
      expect(result[:headings].map { |h| h[:articles] }).to eq([1, 1])
      expect(result[:pairs].first[:both]).to eq(0)
    end
  end

  describe "alias sets" do
    it "saves, retrieves, and lists alias sets" do
      @corpus.save_alias_set("s1", [%w[Plot Synopsis], %w[Career Biography]])
      expect(@corpus.get_alias_set("s1")[:groups]).to eq([%w[Plot Synopsis], %w[Career Biography]])
      expect(@corpus.list_alias_sets.map { |s| s[:name] }).to include("s1")
    end

    it "rejects malformed groups" do
      expect { @corpus.save_alias_set("bad", "not an array") }.to raise_error(ArgumentError)
    end

    it "raises when querying with an unknown alias set" do
      expect { @corpus.find_articles(sections: ["Plot"], alias_set: "nope") }.to raise_error(ArgumentError, /not found/)
    end
  end

  describe "#save_alias_set guardrail" do
    it "blocks groups whose headings frequently coexist in the same articles" do
      result = @corpus.save_alias_set("bad-pair", [%w[Plot Reception]], min_articles: 1)
      expect(result[:saved]).to be false
      expect(result[:violations].first).to include(a: "Plot", b: "Reception")
      expect(@corpus.get_alias_set("bad-pair")).to be_nil
    end

    it "allows an override with force" do
      result = @corpus.save_alias_set("forced", [%w[Plot Reception]], min_articles: 1, force: true)
      expect(result[:saved]).to be true
      expect(@corpus.get_alias_set("forced")).not_to be_nil
    end

    it "passes non-co-occurring groups without force" do
      result = @corpus.save_alias_set("good", [%w[Plot Synopsis]], min_articles: 1)
      expect(result[:saved]).to be true
      expect(result[:violations]).to be_empty
    end

    it "skips pairs below the frequency threshold" do
      result = @corpus.save_alias_set("rare", [%w[Plot Reception]], min_articles: 100)
      expect(result[:saved]).to be true
    end
  end

  describe "#extract_corpus" do
    it "writes JSONL with a reproducibility sidecar and returns a summary with sample" do
      @corpus.save_alias_set("test-plot", [%w[Plot Synopsis]])
      out = File.join(@dir, "plots.jsonl")
      result = @corpus.extract_corpus(
        output_path: out, content: "sections", sections: ["Plot"],
        alias_set: "test-plot", num_processes: 0
      )

      expect(result[:articles_extracted]).to eq(2)
      expect(result[:records_written]).to eq(2)
      expect(result[:truncated]).to be false
      expect(result[:sample].size).to eq(2)

      lines = File.readlines(out).map { |l| JSON.parse(l) }
      expect(lines.size).to eq(2)
      expect(lines.map { |r| r["title"] }).to contain_exactly("Film A", "Film B")
      expect(lines.first["sections"].values.join).to include("Story here")

      meta = JSON.parse(File.read(result[:meta_path]))
      expect(meta["dump"]).to eq("testwiki-20260101")
      expect(meta["alias_set_contents"]).to eq([%w[Plot Synopsis]])
      expect(meta["query"]["resolved_sections"]).to contain_exactly("Plot", "Synopsis")
    end

    it "extracts full article text" do
      out = File.join(@dir, "full.jsonl")
      result = @corpus.extract_corpus(
        output_path: out, content: "full", title_match: "Film A", num_processes: 0
      )
      expect(result[:articles_extracted]).to eq(1)
      record = JSON.parse(File.readlines(out).first)
      expect(record["text"]).to include("Story here")
      expect(record["categories"]).to include("Japanese films")
    end

    it "flags truncation when matches exceed the limit" do
      out = File.join(@dir, "limited.jsonl")
      result = @corpus.extract_corpus(
        output_path: out, content: "sections", sections: %w[Plot Synopsis],
        limit: 1, num_processes: 0
      )
      expect(result[:articles_extracted]).to eq(1)
      expect(result[:truncated]).to be true
      expect(result[:total_matching]).to eq(2)
    end

    it "requires sections or alias_set for sections content" do
      expect do
        @corpus.extract_corpus(output_path: File.join(@dir, "x.jsonl"), content: "sections")
      end.to raise_error(ArgumentError, /requires sections/)
    end

    it "produces one RAG-ready record per chunk when chunk_size is given" do
      out = File.join(@dir, "chunked.jsonl")
      result = @corpus.extract_corpus(
        output_path: out, content: "sections", sections: ["Plot"],
        chunk_size: 5, chunk_overlap: 0, num_processes: 0
      )
      records = File.readlines(out).map { |l| JSON.parse(l) }
      expect(result[:records_written]).to be > result[:articles_extracted]
      expect(records.first).to include("section" => "Plot", "chunk_index" => 0)
      expect(records.first["section_path"]).to eq("Film A > Plot")
      reassembled = records.select { |r| r["title"] == "Film A" }.map { |r| r["text"] }.join
      expect(reassembled).to include("Story here")
      expect(records.map { |r| r["chunk_count"] }.uniq.size).to eq(1)
    end

    it "aborts with Cancelled when cancel_check returns true" do
      out = File.join(@dir, "cancelled.jsonl")
      expect do
        @corpus.extract_corpus(
          output_path: out, content: "full", title_match: "Film",
          num_processes: 0, cancel_check: -> { true }
        )
      end.to raise_error(Wp2txt::Corpus::Cancelled)
    end
  end

  describe "#chunk_text" do
    it "returns the whole text when it fits" do
      expect(@corpus.send(:chunk_text, "short", 100, 0)).to eq(["short"])
    end

    it "prefers sentence boundaries near the window end" do
      text = "One two. Three four five six seven."
      chunks = @corpus.send(:chunk_text, text, 10, 0)
      expect(chunks.first).to eq("One two.")
      expect(chunks.join).to eq(text)
    end

    it "applies overlap between chunks" do
      chunks = @corpus.send(:chunk_text, "abcdefghij", 4, 2)
      expect(chunks.first).to eq("abcd")
      expect(chunks[1]).to start_with("cd")
    end
  end
end

RSpec.describe Wp2txt::CorpusJobManager do
  include MultistreamFixture

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      @multistream_path, @index_path = create_fixture(dir)
      ms_index = Wp2txt::MultistreamIndex.new(@index_path, use_cache: false, show_progress: false)
      db_path = Wp2txt::MetadataIndex.path_for(@multistream_path, cache_dir: dir)
      Wp2txt::MetadataIndexBuilder.new(
        @multistream_path, ms_index.stream_offsets,
        db_path: db_path, num_processes: 0
      ).build
      @manager = described_class.new(-> { Wp2txt::Corpus.for_input(@multistream_path, cache_dir: dir) })
      example.run
    end
  end

  def wait_for(job_id, timeout: 10)
    deadline = Time.now + timeout
    loop do
      status = @manager.status(job_id)
      return status if %w[completed cancelled error].include?(status[:status])
      raise "job timed out: #{status.inspect}" if Time.now > deadline

      sleep 0.05
    end
  end

  it "runs an extraction to completion and reports the result" do
    out = File.join(@dir, "job.jsonl")
    started = @manager.start_extract(
      output_path: out, content: "sections", sections: %w[Plot Synopsis], num_processes: 0
    )
    expect(started[:status]).to eq("running")

    status = wait_for(started[:job_id])
    expect(status[:status]).to eq("completed")
    expect(status[:result][:articles_extracted]).to eq(2)
    expect(status[:progress]).to eq(1.0)
    expect(File.exist?(out)).to be true
  end

  it "reports errors without crashing the manager" do
    started = @manager.start_extract(output_path: File.join(@dir, "x.jsonl"), content: "sections")
    status = wait_for(started[:job_id])
    expect(status[:status]).to eq("error")
    expect(status[:error]).to match(/requires sections/)
  end

  it "returns nil for unknown jobs and lists known ones" do
    expect(@manager.status("job-9999")).to be_nil
    started = @manager.start_extract(
      output_path: File.join(@dir, "l.jsonl"), content: "full", title_match: "Film A", num_processes: 0
    )
    wait_for(started[:job_id])
    expect(@manager.list.map { |j| j[:job_id] }).to include(started[:job_id])
  end
end
