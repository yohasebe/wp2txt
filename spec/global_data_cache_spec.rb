# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Wp2txt::GlobalDataCache do
  let(:cache_dir) { Dir.mktmpdir("wp2txt_global_cache_test_") }

  before do
    described_class.configure(cache_dir: cache_dir, enabled: true)
    described_class.clear!
  end

  after do
    described_class.clear!
    FileUtils.rm_rf(cache_dir)
  end

  describe ".configure" do
    it "sets cache directory" do
      described_class.configure(cache_dir: "/tmp/custom")
      expect(described_class.cache_path).to eq "/tmp/custom/global_data.sqlite3"
    end

    it "can disable caching" do
      described_class.configure(enabled: false)
      expect(described_class.enabled).to be false
    end
  end

  describe ".cache_path" do
    it "returns path to SQLite database" do
      expect(described_class.cache_path).to end_with("global_data.sqlite3")
    end
  end

  describe ".save and .load" do
    it "saves and loads data" do
      test_data = { "key1" => "value1", "nested" => { "a" => 1 } }
      described_class.save(:test_category, test_data)

      loaded = described_class.load(:test_category)
      expect(loaded).to eq test_data
    end

    it "returns nil for non-existent category" do
      expect(described_class.load(:nonexistent)).to be_nil
    end

    it "handles empty hash" do
      described_class.save(:empty, {})
      expect(described_class.load(:empty)).to eq({})
    end

    it "handles arrays in data" do
      test_data = { "list" => [1, 2, 3], "strings" => %w[a b c] }
      described_class.save(:with_arrays, test_data)

      loaded = described_class.load(:with_arrays)
      expect(loaded["list"]).to eq [1, 2, 3]
      expect(loaded["strings"]).to eq %w[a b c]
    end
  end

  describe ".load_all" do
    it "loads all cached categories" do
      described_class.save(:cat1, { "a" => 1 })
      described_class.save(:cat2, { "b" => 2 })

      all = described_class.load_all
      expect(all[:cat1]).to eq({ "a" => 1 })
      expect(all[:cat2]).to eq({ "b" => 2 })
    end

    it "returns empty hash when cache is empty" do
      expect(described_class.load_all).to eq({})
    end
  end

  describe ".save_all" do
    it "saves multiple categories at once" do
      data = {
        cat1: { "x" => 1 },
        cat2: { "y" => 2 }
      }
      described_class.save_all(data)

      expect(described_class.load(:cat1)).to eq({ "x" => 1 })
      expect(described_class.load(:cat2)).to eq({ "y" => 2 })
    end
  end

  describe ".clear!" do
    it "removes the cache file" do
      described_class.save(:test, { "data" => true })
      expect(File.exist?(described_class.cache_path)).to be true

      described_class.clear!
      expect(File.exist?(described_class.cache_path)).to be false
    end
  end

  describe ".stats" do
    it "returns cache statistics" do
      described_class.save(:test, { "data" => "value" })

      stats = described_class.stats
      expect(stats[:cache_path]).to eq described_class.cache_path
      expect(stats[:cache_size]).to be > 0
      expect(stats[:categories]).to be_an(Array)
      expect(stats[:categories].first[:category]).to eq "test"
    end

    it "returns nil when cache doesn't exist" do
      described_class.clear!
      expect(described_class.stats).to be_nil
    end
  end

  describe "caching disabled" do
    before do
      described_class.configure(cache_dir: cache_dir, enabled: false)
    end

    it "does not save data when disabled" do
      described_class.save(:test, { "data" => true })
      expect(File.exist?(described_class.cache_path)).to be false
    end

    it "returns nil when loading with cache disabled" do
      # Enable temporarily to save
      described_class.configure(cache_dir: cache_dir, enabled: true)
      described_class.save(:test, { "data" => true })

      # Disable and try to load
      described_class.configure(cache_dir: cache_dir, enabled: false)
      expect(described_class.load(:test)).to be_nil
    end
  end

  describe "integration with real data files" do
    before do
      described_class.configure(cache_dir: cache_dir, enabled: true)
      described_class.clear!
      # Clear cached instance variables
      Wp2txt.instance_variable_set(:@mediawiki_data, nil)
      Wp2txt.instance_variable_set(:@template_data, nil)
      Wp2txt.instance_variable_set(:@html_entities, nil)
    end

    it "caches mediawiki data" do
      # First load - from JSON
      data1 = Wp2txt.load_mediawiki_data
      expect(data1).to be_a(Hash)
      expect(data1).to have_key("magic_words")

      # Clear instance variable to force reload
      Wp2txt.instance_variable_set(:@mediawiki_data, nil)

      # Second load - from cache
      data2 = Wp2txt.load_mediawiki_data
      expect(data2).to eq data1
    end

    it "caches template data" do
      data1 = Wp2txt.load_template_data
      expect(data1).to be_a(Hash)

      Wp2txt.instance_variable_set(:@template_data, nil)

      data2 = Wp2txt.load_template_data
      expect(data2).to eq data1
    end

    it "caches html entities" do
      data1 = Wp2txt.load_html_entities
      expect(data1).to be_a(Hash)

      Wp2txt.instance_variable_set(:@html_entities, nil)

      data2 = Wp2txt.load_html_entities
      expect(data2).to eq data1
    end
  end
end
