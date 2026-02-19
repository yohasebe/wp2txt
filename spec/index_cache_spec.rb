# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Wp2txt::IndexCache do
  let(:cache_dir) { Dir.mktmpdir("wp2txt_index_cache_test_") }
  let(:source_file) { File.join(cache_dir, "test-index.txt") }
  let(:cache) { described_class.new(source_file, cache_dir: cache_dir) }

  before do
    # Create a dummy source file
    File.write(source_file, "test content")
  end

  after do
    FileUtils.rm_rf(cache_dir)
  end

  describe "#initialize" do
    it "builds cache path from source file" do
      expect(cache.cache_path).to include("test")
      expect(cache.cache_path).to end_with(".sqlite3")
    end

    it "stores source path" do
      expect(cache.source_path).to eq source_file
    end
  end

  describe "#valid?" do
    it "returns false when cache does not exist" do
      expect(cache.valid?).to be false
    end

    it "returns false when source file does not exist" do
      FileUtils.rm_f(source_file)
      expect(cache.valid?).to be false
    end

    context "with saved cache" do
      before do
        entries = {
          "Article 1" => { offset: 1000, page_id: 1, title: "Article 1" },
          "Article 2" => { offset: 2000, page_id: 2, title: "Article 2" }
        }
        cache.save(entries, [0, 1000, 2000])
      end

      it "returns true for valid cache" do
        expect(cache.valid?).to be true
      end

      it "returns false when source file changes" do
        # Modify source file
        sleep 0.1  # Ensure mtime changes
        File.write(source_file, "modified content that is longer")
        expect(cache.valid?).to be false
      end
    end
  end

  describe "#save and #load" do
    let(:entries) do
      {
        "Article A" => { offset: 100, page_id: 1, title: "Article A" },
        "Article B" => { offset: 200, page_id: 2, title: "Article B" },
        "Article C" => { offset: 300, page_id: 3, title: "Article C" }
      }
    end
    let(:stream_offsets) { [0, 100, 200, 300] }

    it "saves and loads entries" do
      cache.save(entries, stream_offsets)

      loaded = cache.load
      expect(loaded[:entries_by_title].size).to eq 3
      expect(loaded[:entries_by_title]["Article A"][:offset]).to eq 100
      expect(loaded[:entries_by_title]["Article B"][:page_id]).to eq 2
    end

    it "saves and loads stream offsets" do
      cache.save(entries, stream_offsets)

      loaded = cache.load
      expect(loaded[:stream_offsets]).to eq stream_offsets
    end

    it "loads entries by ID" do
      cache.save(entries, stream_offsets)

      loaded = cache.load
      expect(loaded[:entries_by_id][1][:title]).to eq "Article A"
      expect(loaded[:entries_by_id][2][:title]).to eq "Article B"
    end

    it "returns nil when cache is invalid" do
      expect(cache.load).to be_nil
    end

    it "handles large number of entries" do
      large_entries = {}
      10_000.times do |i|
        large_entries["Article #{i}"] = { offset: i * 1000, page_id: i, title: "Article #{i}" }
      end

      cache.save(large_entries, [0])
      loaded = cache.load
      expect(loaded[:entries_by_title].size).to eq 10_000
    end

    it "handles Unicode titles" do
      unicode_entries = {
        "東京" => { offset: 100, page_id: 1, title: "東京" },
        "Москва" => { offset: 200, page_id: 2, title: "Москва" },
        "القاهرة" => { offset: 300, page_id: 3, title: "القاهرة" }
      }

      cache.save(unicode_entries, [0])
      loaded = cache.load
      expect(loaded[:entries_by_title]["東京"][:offset]).to eq 100
      expect(loaded[:entries_by_title]["Москва"][:offset]).to eq 200
    end
  end

  describe "#find_by_titles" do
    before do
      entries = {
        "Article 1" => { offset: 100, page_id: 1, title: "Article 1" },
        "Article 2" => { offset: 200, page_id: 2, title: "Article 2" },
        "Article 3" => { offset: 300, page_id: 3, title: "Article 3" }
      }
      cache.save(entries, [0])
    end

    it "finds existing titles" do
      results = cache.find_by_titles(["Article 1", "Article 3"])
      expect(results.size).to eq 2
      expect(results["Article 1"][:offset]).to eq 100
      expect(results["Article 3"][:offset]).to eq 300
    end

    it "ignores non-existent titles" do
      results = cache.find_by_titles(["Article 1", "Nonexistent"])
      expect(results.size).to eq 1
      expect(results).to have_key("Article 1")
      expect(results).not_to have_key("Nonexistent")
    end

    it "returns empty hash for empty input" do
      expect(cache.find_by_titles([])).to eq({})
    end

    it "returns empty hash when cache is invalid" do
      cache.clear!
      expect(cache.find_by_titles(["Article 1"])).to eq({})
    end
  end

  describe "#stats" do
    it "returns cache statistics" do
      entries = {
        "Article 1" => { offset: 100, page_id: 1, title: "Article 1" },
        "Article 2" => { offset: 200, page_id: 2, title: "Article 2" }
      }
      cache.save(entries, [0, 100, 200])

      stats = cache.stats
      expect(stats[:cache_path]).to eq cache.cache_path
      expect(stats[:entry_count]).to eq 2
      expect(stats[:stream_count]).to eq 3
      expect(stats[:cache_size]).to be > 0
    end

    it "returns nil when cache does not exist" do
      expect(cache.stats).to be_nil
    end
  end

  describe "#clear!" do
    it "removes cache file" do
      entries = { "Test" => { offset: 100, page_id: 1, title: "Test" } }
      cache.save(entries, [0])

      expect(File.exist?(cache.cache_path)).to be true
      cache.clear!
      expect(File.exist?(cache.cache_path)).to be false
    end
  end

  describe "concurrent access" do
    it "handles multiple readers" do
      entries = { "Test" => { offset: 100, page_id: 1, title: "Test" } }
      cache.save(entries, [0])

      # Simulate multiple readers
      results = 3.times.map do
        Thread.new do
          c = described_class.new(source_file, cache_dir: cache_dir)
          c.load
        end
      end.map(&:value)

      results.each do |result|
        expect(result[:entries_by_title]).to have_key("Test")
      end
    end
  end
end
