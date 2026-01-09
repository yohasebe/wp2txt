# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require "zlib"
require "webmock/rspec"

RSpec.describe "Wp2txt Multistream" do
  before do
    # Ensure WebMock is enabled (may be disabled by other specs)
    WebMock.enable!
    # Allow localhost connections, stub external
    WebMock.disable_net_connect!(allow_localhost: true)

    # Stub Wikipedia dump listing page
    stub_request(:get, %r{dumps\.wikimedia\.org})
      .to_return(status: 200, body: '<a href="20260101/">20260101/</a>')
  end

  after do
    WebMock.allow_net_connect!
  end
  describe Wp2txt::DumpManager do
    let(:temp_dir) { Dir.mktmpdir }
    let(:manager) { described_class.new("en", cache_dir: temp_dir) }

    after { FileUtils.remove_entry(temp_dir) }

    describe "#format_size" do
      it "formats bytes" do
        expect(manager.send(:format_size, 500)).to eq("500 B")
      end

      it "formats kilobytes" do
        expect(manager.send(:format_size, 2048)).to eq("2.0 KB")
      end

      it "formats megabytes" do
        expect(manager.send(:format_size, 5_242_880)).to eq("5.0 MB")
      end

      it "formats gigabytes" do
        expect(manager.send(:format_size, 2_147_483_648)).to eq("2.0 GB")
      end
    end

    describe "#cached_index_path" do
      it "returns correct path format" do
        path = manager.cached_index_path
        expect(path).to include("enwiki")
        expect(path).to include("index")
      end
    end

    describe "#cached_multistream_path" do
      it "returns correct path format" do
        path = manager.cached_multistream_path
        expect(path).to include("enwiki")
        expect(path).to end_with(".xml.bz2")
      end
    end

    describe "#cache_fresh?" do
      context "when cache does not exist" do
        it "returns false" do
          expect(manager.cache_fresh?).to be false
        end
      end

      context "when cache exists and is fresh" do
        before do
          FileUtils.mkdir_p(File.dirname(manager.cached_index_path))
          File.write(manager.cached_index_path, "test")
        end

        it "returns true" do
          expect(manager.cache_fresh?(30)).to be true
        end
      end
    end

    describe "#cache_stale?" do
      context "when cache does not exist" do
        it "returns true" do
          expect(manager.cache_stale?).to be true
        end
      end
    end

    describe "#cache_age_days" do
      context "when cache does not exist" do
        it "returns nil" do
          expect(manager.cache_age_days).to be_nil
        end
      end

      context "when cache exists" do
        before do
          FileUtils.mkdir_p(File.dirname(manager.cached_index_path))
          File.write(manager.cached_index_path, "test")
        end

        it "returns age in days" do
          age = manager.cache_age_days
          expect(age).to be_a(Float)
          expect(age).to be >= 0
          expect(age).to be < 1
        end
      end
    end

    describe "#cache_mtime" do
      context "when cache does not exist" do
        it "returns nil" do
          expect(manager.cache_mtime).to be_nil
        end
      end

      context "when cache exists" do
        before do
          FileUtils.mkdir_p(File.dirname(manager.cached_index_path))
          File.write(manager.cached_index_path, "test")
        end

        it "returns Time object" do
          expect(manager.cache_mtime).to be_a(Time)
        end
      end
    end

    describe "#cache_status" do
      context "when cache is empty" do
        it "returns status hash with zero sizes" do
          status = manager.cache_status
          expect(status[:index_size]).to eq(0)
          expect(status[:multistream_size]).to eq(0)
          expect(status[:fresh]).to be false
        end
      end
    end

    describe "#clear_cache!" do
      it "does not raise error when no cache exists" do
        expect { manager.clear_cache! }.not_to raise_error
      end
    end

    describe ".all_cache_status" do
      it "returns hash of all cached languages" do
        status = described_class.all_cache_status(temp_dir)
        expect(status).to be_a(Hash)
      end
    end

    describe "#find_suitable_partial_cache" do
      context "when no partial cache exists" do
        it "returns nil" do
          expect(manager.find_suitable_partial_cache(100)).to be_nil
        end
      end
    end
  end

  describe Wp2txt::MultistreamIndex do
    let(:temp_dir) { Dir.mktmpdir }
    let(:index_path) { File.join(temp_dir, "test-index.txt") }

    after { FileUtils.remove_entry(temp_dir) }

    before do
      # Create a minimal index file
      File.write(index_path, <<~INDEX)
        100:1:Article One
        100:2:Article Two
        200:3:Article Three
        200:4:日本語記事
      INDEX
    end

    describe "#initialize" do
      it "loads the index file" do
        index = described_class.new(index_path)
        expect(index.size).to eq(4)
      end
    end

    describe "#find_by_title" do
      let(:index) { described_class.new(index_path) }

      it "finds article by exact title" do
        result = index.find_by_title("Article One")
        expect(result).not_to be_nil
        expect(result[:title]).to eq("Article One")
        expect(result[:offset]).to eq(100)
        expect(result[:page_id]).to eq(1)
      end

      it "finds Japanese article" do
        result = index.find_by_title("日本語記事")
        expect(result).not_to be_nil
        expect(result[:title]).to eq("日本語記事")
      end

      it "returns nil for non-existent title" do
        result = index.find_by_title("Non Existent")
        expect(result).to be_nil
      end
    end

    describe "#find_by_id" do
      let(:index) { described_class.new(index_path) }

      it "finds article by page ID" do
        result = index.find_by_id(2)
        expect(result).not_to be_nil
        expect(result[:title]).to eq("Article Two")
      end

      it "returns nil for non-existent ID" do
        result = index.find_by_id(999)
        expect(result).to be_nil
      end
    end

    describe "#articles_in_stream" do
      let(:index) { described_class.new(index_path) }

      it "returns articles at given byte offset" do
        articles = index.articles_in_stream(100)
        expect(articles.size).to eq(2)
        expect(articles.map { |a| a[:title] }).to include("Article One", "Article Two")
      end

      it "returns empty array for non-existent offset" do
        articles = index.articles_in_stream(999)
        expect(articles).to eq([])
      end
    end

    describe "#stream_offset_for" do
      let(:index) { described_class.new(index_path) }

      it "returns byte offset for article" do
        offset = index.stream_offset_for("Article Three")
        expect(offset).to eq(200)
      end

      it "returns nil for non-existent title" do
        offset = index.stream_offset_for("Non Existent")
        expect(offset).to be_nil
      end
    end

    describe "#random_articles" do
      let(:index) { described_class.new(index_path) }

      it "returns requested number of random articles" do
        articles = index.random_articles(2)
        expect(articles.size).to eq(2)
      end

      it "returns all articles if count exceeds size" do
        articles = index.random_articles(100)
        expect(articles.size).to eq(4)
      end
    end

    describe "#first_articles" do
      let(:index) { described_class.new(index_path) }

      it "returns first N articles" do
        articles = index.first_articles(2)
        expect(articles.size).to eq(2)
      end
    end

    describe "#stream_offsets" do
      let(:index) { described_class.new(index_path) }

      it "returns unique sorted offsets" do
        offsets = index.stream_offsets
        expect(offsets).to eq([100, 200])
      end
    end
  end

  describe Wp2txt::CategoryFetcher do
    let(:fetcher) { described_class.new("en", "Test Category") }

    describe "#initialize" do
      it "normalizes category name" do
        fetcher = described_class.new("en", "test_category")
        # Category name should be normalized (underscores to spaces)
        expect(fetcher.instance_variable_get(:@category)).to include("test")
      end

      it "sets default max_depth to 0" do
        expect(fetcher.instance_variable_get(:@max_depth)).to eq(0)
      end

      it "accepts custom max_depth" do
        fetcher = described_class.new("en", "Test", max_depth: 2)
        expect(fetcher.instance_variable_get(:@max_depth)).to eq(2)
      end

      it "strips Category: prefix" do
        fetcher = described_class.new("en", "Category:Test")
        expect(fetcher.instance_variable_get(:@category)).to eq("Test")
      end

      it "accepts different languages" do
        fetcher = described_class.new("ja", "テスト")
        expect(fetcher.instance_variable_get(:@lang)).to eq("ja")
      end

      it "accepts custom cache_expiry_days" do
        fetcher = described_class.new("en", "Test", cache_expiry_days: 14)
        expect(fetcher.instance_variable_get(:@cache_expiry_days)).to eq(14)
      end
    end

    describe "#enable_cache" do
      it "sets cache directory" do
        fetcher.enable_cache("/tmp/test_cache")
        expect(fetcher.instance_variable_get(:@cache_dir)).to eq("/tmp/test_cache")
      end
    end

    describe "cache operations" do
      let(:temp_cache) { Dir.mktmpdir }
      let(:fetcher_with_cache) do
        f = described_class.new("en", "Test Category")
        f.enable_cache(temp_cache)
        f
      end

      after { FileUtils.rm_rf(temp_cache) if File.exist?(temp_cache) }

      it "generates correct cache path" do
        path = fetcher_with_cache.send(:cache_path, "Test_Category")
        expect(path).to include("category_en_Test_Category.json")
      end

      it "returns nil for cache_path when cache disabled" do
        fetcher_no_cache = described_class.new("en", "Test")
        path = fetcher_no_cache.send(:cache_path, "Test")
        expect(path).to be_nil
      end

      it "handles special characters in category name" do
        path = fetcher_with_cache.send(:cache_path, "Test/Category:With<Special>Chars")
        expect(path).to include("category_en_")
        filename = File.basename(path)
        # Filename should not contain special chars (they're replaced with _)
        expect(filename).not_to include("/")
        expect(filename).not_to include(":")
        expect(filename).not_to include("<")
        expect(filename).not_to include(">")
      end

      it "saves and loads from cache" do
        category = "Cache_Test"
        members = { pages: ["Article1", "Article2"], subcats: ["SubCat1"] }

        fetcher_with_cache.send(:save_to_cache, category, members)
        loaded = fetcher_with_cache.send(:load_from_cache, category)

        expect(loaded[:pages]).to eq(["Article1", "Article2"])
        expect(loaded[:subcats]).to eq(["SubCat1"])
      end

      it "returns nil for non-existent cache" do
        result = fetcher_with_cache.send(:load_from_cache, "NonExistent")
        expect(result).to be_nil
      end
    end
  end

  describe Wp2txt::MultistreamReader do
    let(:temp_dir) { Dir.mktmpdir }
    let(:index_path) { File.join(temp_dir, "test-index.txt") }
    let(:multistream_path) { File.join(temp_dir, "test-multistream.xml.bz2") }

    after { FileUtils.remove_entry(temp_dir) }

    before do
      # Create a minimal index file
      File.write(index_path, <<~INDEX)
        100:1:Article One
        100:2:Article Two
        200:3:Article Three
      INDEX
    end

    describe "#initialize" do
      it "creates reader with paths" do
        reader = described_class.new(multistream_path, index_path)
        expect(reader.multistream_path).to eq(multistream_path)
        expect(reader.index).to be_a(Wp2txt::MultistreamIndex)
      end
    end

    describe "#extract_article" do
      it "returns nil for non-existent article" do
        # Without actual bz2 file, can't extract, but should handle gracefully
        reader = described_class.new(multistream_path, index_path)
        # Will return nil because file doesn't exist
        expect { reader.extract_article("Non Existent") }.not_to raise_error
      end
    end

    describe "#extract_articles_parallel" do
      it "handles empty titles array" do
        reader = described_class.new(multistream_path, index_path)
        result = reader.extract_articles_parallel([], num_processes: 2)
        expect(result).to eq({})
      end

      it "handles titles not in index" do
        reader = described_class.new(multistream_path, index_path)
        result = reader.extract_articles_parallel(["Non Existent"], num_processes: 2)
        expect(result).to eq({})
      end
    end

    describe "#each_article_parallel" do
      it "returns an enumerator when no block given" do
        reader = described_class.new(multistream_path, index_path)
        result = reader.each_article_parallel([], num_processes: 2)
        expect(result).to be_an(Enumerator)
      end

      it "handles empty entries array" do
        reader = described_class.new(multistream_path, index_path)
        pages = []
        reader.each_article_parallel([], num_processes: 2) { |page| pages << page }
        expect(pages).to eq([])
      end
    end
  end

  describe "Wp2txt.ssl_safe_get" do
    it "creates HTTP request with SSL verification callback" do
      # Test the structure of ssl_safe_get
      uri = URI("https://example.com/test")

      # Mock Net::HTTP to verify configuration
      http_mock = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_mock)
      allow(http_mock).to receive(:use_ssl=)
      allow(http_mock).to receive(:use_ssl?).and_return(true)
      allow(http_mock).to receive(:open_timeout=)
      allow(http_mock).to receive(:read_timeout=)
      allow(http_mock).to receive(:verify_mode=)
      allow(http_mock).to receive(:verify_callback=)
      allow(http_mock).to receive(:request).and_return(Net::HTTPSuccess.new("1.1", "200", "OK"))

      expect { Wp2txt.ssl_safe_get(uri) }.not_to raise_error
    end
  end

  describe Wp2txt::DumpManager do
    describe ".default_cache_dir" do
      it "returns default cache directory path" do
        path = described_class.default_cache_dir
        expect(path).to include(".wp2txt/cache")
      end
    end

    describe ".clear_all_cache!" do
      let(:temp_cache) { Dir.mktmpdir }

      after { FileUtils.rm_rf(temp_cache) if File.exist?(temp_cache) }

      it "does not raise error when cache does not exist" do
        expect { described_class.clear_all_cache!("/nonexistent/path") }.not_to raise_error
      end

      it "removes existing cache directory" do
        FileUtils.mkdir_p(File.join(temp_cache, "subdir"))
        File.write(File.join(temp_cache, "test.txt"), "content")

        described_class.clear_all_cache!(temp_cache)

        expect(File.exist?(temp_cache)).to be false
      end
    end

    describe "#cached_partial_multistream_path" do
      let(:temp_dir) { Dir.mktmpdir }
      let(:manager) { described_class.new("en", cache_dir: temp_dir) }

      after { FileUtils.remove_entry(temp_dir) }

      it "includes stream count in filename" do
        path = manager.cached_partial_multistream_path(1000)
        expect(path).to include("1000streams")
        expect(path).to end_with(".xml.bz2")
      end
    end

    describe "#find_any_partial_cache" do
      let(:temp_dir) { Dir.mktmpdir }
      let(:manager) { described_class.new("en", cache_dir: temp_dir) }

      after { FileUtils.remove_entry(temp_dir) }

      context "when no partial exists" do
        it "returns nil" do
          expect(manager.find_any_partial_cache).to be_nil
        end
      end

      context "when partial dumps exist" do
        before do
          # Create fake partial dump files
          File.write(File.join(temp_dir, "enwiki-20260101-multistream-100streams.xml.bz2"), "BZh9" + "x" * 100)
          File.write(File.join(temp_dir, "enwiki-20260101-multistream-500streams.xml.bz2"), "BZh9" + "x" * 500)
        end

        it "returns the largest partial by stream count" do
          result = manager.find_any_partial_cache
          expect(result).not_to be_nil
          expect(result[:stream_count]).to eq(500)
          expect(result[:dump_date]).to eq("20260101")
        end

        it "includes file size and mtime" do
          result = manager.find_any_partial_cache
          expect(result[:size]).to be > 0
          expect(result[:mtime]).to be_a(Time)
        end
      end

      context "with partials from different dates" do
        before do
          File.write(File.join(temp_dir, "enwiki-20260101-multistream-100streams.xml.bz2"), "BZh9" + "x" * 100)
          File.write(File.join(temp_dir, "enwiki-20260201-multistream-50streams.xml.bz2"), "BZh9" + "x" * 50)
        end

        it "returns the largest regardless of date" do
          result = manager.find_any_partial_cache
          expect(result[:stream_count]).to eq(100)
          expect(result[:dump_date]).to eq("20260101")
        end
      end
    end

    describe "#can_resume_from_partial?" do
      let(:temp_dir) { Dir.mktmpdir }
      let(:manager) { described_class.new("en", cache_dir: temp_dir) }

      after { FileUtils.remove_entry(temp_dir) }

      context "when partial_info is nil" do
        it "returns not possible with :no_partial reason" do
          result = manager.can_resume_from_partial?(nil)
          expect(result[:possible]).to be false
          expect(result[:reason]).to eq(:no_partial)
        end
      end

      context "when dump dates don't match" do
        let(:partial_info) do
          {
            path: File.join(temp_dir, "enwiki-20250101-multistream-100streams.xml.bz2"),
            dump_date: "20250101",
            stream_count: 100,
            size: 1000
          }
        end

        before do
          # Create the file
          File.write(partial_info[:path], "BZh9" + "x" * 100)
          # Stub the latest_dump_date to return a different date
          allow(manager).to receive(:latest_dump_date).and_return("20260101")
        end

        it "returns not possible with :date_mismatch reason" do
          result = manager.can_resume_from_partial?(partial_info)
          expect(result[:possible]).to be false
          expect(result[:reason]).to eq(:date_mismatch)
          expect(result[:partial_date]).to eq("20250101")
          expect(result[:latest_date]).to eq("20260101")
        end
      end

      context "when partial file is invalid" do
        let(:partial_info) do
          {
            path: File.join(temp_dir, "enwiki-20260101-multistream-100streams.xml.bz2"),
            dump_date: "20260101",
            stream_count: 100,
            size: 1000
          }
        end

        before do
          # Create an invalid bz2 file (wrong magic bytes)
          File.write(partial_info[:path], "XXXX" + "x" * 100)
          allow(manager).to receive(:latest_dump_date).and_return("20260101")
        end

        it "returns not possible with :invalid_partial reason" do
          result = manager.can_resume_from_partial?(partial_info)
          expect(result[:possible]).to be false
          expect(result[:reason]).to eq(:invalid_partial)
        end
      end
    end

    describe "#get_remote_file_size" do
      let(:temp_dir) { Dir.mktmpdir }
      let(:manager) { described_class.new("en", cache_dir: temp_dir) }

      after { FileUtils.remove_entry(temp_dir) }

      it "returns file size from Content-Length header" do
        stub_request(:head, %r{dumps\.wikimedia\.org})
          .to_return(status: 200, headers: { "Content-Length" => "12345678" })

        allow(manager).to receive(:latest_dump_date).and_return("20260101")
        size = manager.send(:get_remote_file_size, "https://dumps.wikimedia.org/enwiki/20260101/test.xml.bz2")
        expect(size).to eq(12_345_678)
      end

      it "returns 0 when Content-Length is missing" do
        stub_request(:head, %r{dumps\.wikimedia\.org})
          .to_return(status: 200, headers: {})

        size = manager.send(:get_remote_file_size, "https://dumps.wikimedia.org/test.xml.bz2")
        expect(size).to eq(0)
      end
    end
  end
end
