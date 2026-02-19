# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Wp2txt::CategoryCache do
  let(:cache_dir) { Dir.mktmpdir("wp2txt_category_cache_test_") }
  let(:cache) { described_class.new("en", cache_dir: cache_dir) }

  after do
    cache.close
    FileUtils.rm_rf(cache_dir)
  end

  describe "#initialize" do
    it "creates cache file" do
      expect(File.exist?(cache.cache_path)).to be true
    end

    it "sets language" do
      expect(cache.lang).to eq "en"
    end

    it "uses default expiry days" do
      expect(cache.expiry_days).to eq Wp2txt::DEFAULT_CATEGORY_CACHE_EXPIRY_DAYS
    end

    it "accepts custom expiry days" do
      custom_cache = described_class.new("ja", cache_dir: cache_dir, expiry_days: 14)
      expect(custom_cache.expiry_days).to eq 14
      custom_cache.close
    end
  end

  describe "#save and #get" do
    it "saves and retrieves category data" do
      pages = ["Article 1", "Article 2", "Article 3"]
      subcats = ["Subcategory A", "Subcategory B"]

      cache.save("Test Category", pages, subcats)
      data = cache.get("Test Category")

      expect(data[:pages]).to eq pages
      expect(data[:subcats]).to eq subcats
    end

    it "handles empty pages" do
      cache.save("Empty Pages", [], ["Subcat"])
      data = cache.get("Empty Pages")

      expect(data[:pages]).to eq []
      expect(data[:subcats]).to eq ["Subcat"]
    end

    it "handles empty subcategories" do
      cache.save("No Subcats", ["Article"], [])
      data = cache.get("No Subcats")

      expect(data[:pages]).to eq ["Article"]
      expect(data[:subcats]).to eq []
    end

    it "handles Unicode category names" do
      cache.save("日本の都市", ["東京", "大阪"], ["関東の都市"])
      data = cache.get("日本の都市")

      expect(data[:pages]).to contain_exactly("東京", "大阪")
      expect(data[:subcats]).to contain_exactly("関東の都市")
    end

    it "normalizes category name by removing Category: prefix" do
      cache.save("Category:Test", ["Article"], [])
      data = cache.get("Test")

      expect(data[:pages]).to eq ["Article"]
    end

    it "returns nil for non-existent category" do
      expect(cache.get("Nonexistent")).to be_nil
    end
  end

  describe "#cached?" do
    it "returns true for cached category" do
      cache.save("Cached", ["Article"], [])
      expect(cache.cached?("Cached")).to be true
    end

    it "returns false for non-cached category" do
      expect(cache.cached?("Not Cached")).to be false
    end
  end

  describe "#get_all_pages" do
    before do
      cache.save("Root", ["Article1", "Article2"], ["Child1", "Child2"])
      cache.save("Child1", ["Article3"], ["Grandchild"])
      cache.save("Child2", ["Article4", "Article5"], [])
      cache.save("Grandchild", ["Article6"], [])
    end

    it "returns only direct pages with max_depth 0" do
      pages = cache.get_all_pages("Root", max_depth: 0)
      expect(pages).to contain_exactly("Article1", "Article2")
    end

    it "includes subcategory pages with max_depth 1" do
      pages = cache.get_all_pages("Root", max_depth: 1)
      expect(pages).to contain_exactly("Article1", "Article2", "Article3", "Article4", "Article5")
    end

    it "includes all nested pages with sufficient depth" do
      pages = cache.get_all_pages("Root", max_depth: 2)
      expect(pages).to contain_exactly("Article1", "Article2", "Article3", "Article4", "Article5", "Article6")
    end

    it "returns unique pages (no duplicates)" do
      cache.save("DupParent", ["SharedArticle"], ["DupChild"])
      cache.save("DupChild", ["SharedArticle", "UniqueArticle"], [])

      pages = cache.get_all_pages("DupParent", max_depth: 1)
      expect(pages.count("SharedArticle")).to eq 1
    end

    it "handles circular references" do
      cache.save("CircularA", ["A1"], ["CircularB"])
      cache.save("CircularB", ["B1"], ["CircularA"])

      pages = cache.get_all_pages("CircularA", max_depth: 10)
      expect(pages).to contain_exactly("A1", "B1")
    end

    it "returns empty array for non-existent category" do
      expect(cache.get_all_pages("Nonexistent")).to eq []
    end
  end

  describe "#get_tree" do
    before do
      cache.save("Root", ["A1"], ["Child"])
      cache.save("Child", ["C1", "C2"], [])
    end

    it "returns tree structure" do
      tree = cache.get_tree("Root", max_depth: 1)

      expect(tree[:name]).to eq "Root"
      expect(tree[:cached]).to be true
      expect(tree[:page_count]).to eq 1
      expect(tree[:children].size).to eq 1
      expect(tree[:children].first[:name]).to eq "Child"
    end

    it "limits depth" do
      cache.save("Deep", ["D1"], ["Root"])

      tree = cache.get_tree("Deep", max_depth: 0)
      expect(tree[:children]).to be_empty
    end
  end

  describe "#stats" do
    it "returns cache statistics" do
      cache.save("Cat1", ["A1", "A2"], ["Sub1"])
      cache.save("Cat2", ["A3"], [])

      stats = cache.stats

      expect(stats[:lang]).to eq "en"
      expect(stats[:total_categories]).to eq 2
      expect(stats[:total_pages]).to eq 3
      expect(stats[:total_relations]).to eq 1
      expect(stats[:cache_size]).to be > 0
    end
  end

  describe "#clear!" do
    it "removes all cached data" do
      cache.save("Test", ["Article"], [])
      cache.clear!

      expect(cache.cached?("Test")).to be false
    end
  end

  describe "#cleanup_expired!" do
    it "removes expired entries" do
      # Save a category
      cache.save("Old", ["Article"], [])

      # Manually update the cached_at to make it old
      # We need to access the database directly for this test
      cache.instance_variable_get(:@db).execute(
        "UPDATE categories SET cached_at = ? WHERE name = ?",
        [Time.now.to_i - (30 * 24 * 3600), "Old"]  # 30 days ago
      )

      # Save a fresh category
      cache.save("Fresh", ["NewArticle"], [])

      # Cleanup with default 7-day expiry
      removed = cache.cleanup_expired!

      expect(removed).to eq 1
      expect(cache.cached?("Old")).to be false
      expect(cache.cached?("Fresh")).to be true
    end
  end

  describe "per-language isolation" do
    it "creates separate cache per language" do
      en_cache = described_class.new("en", cache_dir: cache_dir)
      ja_cache = described_class.new("ja", cache_dir: cache_dir)

      en_cache.save("Cities", ["New York"], [])
      ja_cache.save("Cities", ["東京"], [])

      expect(en_cache.get("Cities")[:pages]).to eq ["New York"]
      expect(ja_cache.get("Cities")[:pages]).to eq ["東京"]

      en_cache.close
      ja_cache.close
    end
  end
end
