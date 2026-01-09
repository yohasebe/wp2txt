# frozen_string_literal: true

require_relative "spec_helper"
require "webmock/rspec"
require "tmpdir"
require "fileutils"

RSpec.describe Wp2txt::CategoryFetcher do
  let(:lang) { "en" }
  let(:category) { "Japanese cities" }
  let(:fetcher) { described_class.new(lang, category) }

  before do
    WebMock.enable!
    WebMock.disable_net_connect!
  end

  after do
    WebMock.disable!
  end

  describe "#initialize" do
    it "accepts language and category name" do
      expect(fetcher.lang).to eq "en"
      expect(fetcher.category).to eq "Japanese cities"
    end

    it "normalizes category name by removing Category: prefix" do
      f = described_class.new("en", "Category:Test Category")
      expect(f.category).to eq "Test Category"
    end

    it "handles lowercase category prefix" do
      f = described_class.new("en", "category:Another Test")
      expect(f.category).to eq "Another Test"
    end

    it "trims whitespace from category name" do
      f = described_class.new("en", "  Test Category  ")
      expect(f.category).to eq "Test Category"
    end

    it "defaults max_depth to 0" do
      expect(fetcher.max_depth).to eq 0
    end

    it "accepts custom max_depth" do
      f = described_class.new("ja", "Test", max_depth: 3)
      expect(f.max_depth).to eq 3
    end
  end

  describe "#fetch_preview" do
    it "returns statistics without full article list" do
      stub_request(:get, /en\.wikipedia\.org/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Tokyo" },
                { ns: 0, title: "Osaka" },
                { ns: 0, title: "Kyoto" }
              ]
            }
          }.to_json
        )

      preview = fetcher.fetch_preview

      expect(preview[:category]).to eq "Japanese cities"
      expect(preview[:depth]).to eq 0
      expect(preview[:total_articles]).to eq 3
      expect(preview[:subcategories]).to be_an(Array)
    end

    it "includes subcategory statistics when depth > 0" do
      f = described_class.new("en", "Japanese cities", max_depth: 1)

      # Parent category
      stub_request(:get, /cmtitle=Category:Japanese%20cities/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Tokyo" },
                { ns: 14, title: "Category:Cities in Kanto" }
              ]
            }
          }.to_json
        )

      # Subcategory
      stub_request(:get, /cmtitle=Category:Cities%20in%20Kanto/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Yokohama" },
                { ns: 0, title: "Chiba" }
              ]
            }
          }.to_json
        )

      preview = f.fetch_preview

      expect(preview[:total_articles]).to eq 3
      expect(preview[:total_subcategories]).to eq 1
      expect(preview[:subcategories].size).to eq 2
    end
  end

  describe "#fetch_articles" do
    it "fetches articles from single page response" do
      stub_request(:get, /en\.wikipedia\.org/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Tokyo" },
                { ns: 0, title: "Osaka" },
                { ns: 0, title: "Kyoto" }
              ]
            }
          }.to_json
        )

      articles = fetcher.fetch_articles
      expect(articles).to contain_exactly("Tokyo", "Osaka", "Kyoto")
    end

    it "handles pagination with cmcontinue token" do
      # First request
      stub_request(:get, /en\.wikipedia\.org/)
        .with(query: hash_excluding("cmcontinue"))
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Article1" },
                { ns: 0, title: "Article2" }
              ]
            },
            continue: { cmcontinue: "page2token" }
          }.to_json
        )

      # Second request with continue token
      stub_request(:get, /en\.wikipedia\.org/)
        .with(query: hash_including("cmcontinue" => "page2token"))
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Article3" }
              ]
            }
          }.to_json
        )

      articles = fetcher.fetch_articles
      expect(articles.size).to eq 3
      expect(articles).to include("Article1", "Article2", "Article3")
    end

    it "returns unique articles when duplicates exist" do
      stub_request(:get, /en\.wikipedia\.org/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Tokyo" },
                { ns: 0, title: "Tokyo" },
                { ns: 0, title: "Osaka" }
              ]
            }
          }.to_json
        )

      articles = fetcher.fetch_articles
      expect(articles).to contain_exactly("Tokyo", "Osaka")
    end

    it "returns empty array for non-existent category" do
      stub_request(:get, /en\.wikipedia\.org/)
        .to_return(
          status: 200,
          body: { query: { categorymembers: [] } }.to_json
        )

      articles = fetcher.fetch_articles
      expect(articles).to be_empty
    end

    it "handles API errors gracefully" do
      stub_request(:get, /en\.wikipedia\.org/)
        .to_return(status: 500)

      articles = fetcher.fetch_articles
      expect(articles).to be_empty
    end

    it "handles network timeout gracefully" do
      stub_request(:get, /en\.wikipedia\.org/)
        .to_timeout

      articles = fetcher.fetch_articles
      expect(articles).to be_empty
    end

    it "handles malformed JSON response gracefully" do
      stub_request(:get, /en\.wikipedia\.org/)
        .to_return(
          status: 200,
          body: "not valid json"
        )

      articles = fetcher.fetch_articles
      expect(articles).to be_empty
    end
  end

  describe "subcategory recursion" do
    it "does not recurse into subcategories when max_depth is 0" do
      stub_request(:get, /cmtitle=Category:Japanese%20cities/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Tokyo" },
                { ns: 14, title: "Category:Cities in Kanto" }
              ]
            }
          }.to_json
        )

      articles = fetcher.fetch_articles
      expect(articles).to eq ["Tokyo"]
      expect(WebMock).not_to have_requested(:get, /cmtitle=Category:Cities%20in%20Kanto/)
    end

    it "recurses into subcategories when max_depth > 0" do
      f = described_class.new("en", "Japanese cities", max_depth: 1)

      # Parent category
      stub_request(:get, /cmtitle=Category:Japanese%20cities/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Tokyo" },
                { ns: 14, title: "Category:Cities in Kanto" }
              ]
            }
          }.to_json
        )

      # Subcategory
      stub_request(:get, /cmtitle=Category:Cities%20in%20Kanto/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Yokohama" },
                { ns: 0, title: "Chiba" }
              ]
            }
          }.to_json
        )

      articles = f.fetch_articles
      expect(articles).to contain_exactly("Tokyo", "Yokohama", "Chiba")
    end

    it "prevents infinite loops with circular category references" do
      f = described_class.new("en", "Category A", max_depth: 5)

      stub_request(:get, /cmtitle=Category:Category%20A/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Article1" },
                { ns: 14, title: "Category:Category B" }
              ]
            }
          }.to_json
        )

      stub_request(:get, /cmtitle=Category:Category%20B/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Article2" },
                { ns: 14, title: "Category:Category A" }
              ]
            }
          }.to_json
        )

      # Should complete without infinite loop
      expect { f.fetch_articles }.not_to raise_error
      articles = f.fetch_articles
      expect(articles).to include("Article1", "Article2")
    end

    it "respects max_depth limit" do
      f = described_class.new("en", "Root", max_depth: 1)

      # Root
      stub_request(:get, /cmtitle=Category:Root/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 14, title: "Category:Level1" }
              ]
            }
          }.to_json
        )

      # Level 1
      stub_request(:get, /cmtitle=Category:Level1/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [
                { ns: 0, title: "Article1" },
                { ns: 14, title: "Category:Level2" }
              ]
            }
          }.to_json
        )

      # Level 2 should not be called
      stub_request(:get, /cmtitle=Category:Level2/)
        .to_return(
          status: 200,
          body: {
            query: { categorymembers: [{ ns: 0, title: "Article2" }] }
          }.to_json
        )

      articles = f.fetch_articles
      expect(articles).to eq ["Article1"]
      expect(WebMock).not_to have_requested(:get, /cmtitle=Category:Level2/)
    end
  end

  describe "caching" do
    let(:cache_dir) { Dir.mktmpdir("wp2txt_test_") }

    after do
      FileUtils.rm_rf(cache_dir)
    end

    it "caches category members to disk" do
      f = described_class.new("en", "Test Category")
      f.enable_cache(cache_dir)

      stub_request(:get, /en\.wikipedia\.org/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [{ ns: 0, title: "Cached Article" }]
            }
          }.to_json
        )

      f.fetch_articles

      # Cache file should exist
      cache_files = Dir.glob(File.join(cache_dir, "category_*.json"))
      expect(cache_files.size).to eq 1
    end

    it "uses cached data on subsequent calls" do
      f = described_class.new("en", "Test Category")
      f.enable_cache(cache_dir)

      # Pre-populate cache
      cache_path = File.join(cache_dir, "category_en_Test_Category.json")
      File.write(cache_path, { pages: ["Cached Article"], subcats: [] }.to_json)

      # Should not make API request
      articles = f.fetch_articles
      expect(articles).to eq ["Cached Article"]
      expect(WebMock).not_to have_requested(:get, /wikipedia\.org/)
    end

    it "ignores stale cache" do
      f = described_class.new("en", "Test Category")
      f.enable_cache(cache_dir)

      # Pre-populate stale cache (8 days old)
      cache_path = File.join(cache_dir, "category_en_Test_Category.json")
      File.write(cache_path, { pages: ["Old Article"], subcats: [] }.to_json)
      File.utime(Time.now - (8 * 24 * 3600), Time.now - (8 * 24 * 3600), cache_path)

      stub_request(:get, /en\.wikipedia\.org/)
        .to_return(
          status: 200,
          body: {
            query: {
              categorymembers: [{ ns: 0, title: "Fresh Article" }]
            }
          }.to_json
        )

      articles = f.fetch_articles
      expect(articles).to eq ["Fresh Article"]
    end
  end

  describe "special characters in category names" do
    it "handles spaces in category names" do
      f = described_class.new("en", "Japanese cities")

      stub_request(:get, /cmtitle=Category:Japanese%20cities/)
        .to_return(
          status: 200,
          body: { query: { categorymembers: [{ ns: 0, title: "Tokyo" }] } }.to_json
        )

      articles = f.fetch_articles
      expect(articles).to eq ["Tokyo"]
    end

    it "handles Unicode category names" do
      f = described_class.new("ja", "日本の都市")

      stub_request(:get, /ja\.wikipedia\.org/)
        .to_return(
          status: 200,
          body: { query: { categorymembers: [{ ns: 0, title: "東京" }] } }.to_json
        )

      articles = f.fetch_articles
      expect(articles).to eq ["東京"]
    end

    it "handles special characters in category names" do
      f = described_class.new("en", "Rock & Roll")

      stub_request(:get, /cmtitle=Category:Rock%20%26%20Roll/)
        .to_return(
          status: 200,
          body: { query: { categorymembers: [{ ns: 0, title: "Elvis" }] } }.to_json
        )

      articles = f.fetch_articles
      expect(articles).to eq ["Elvis"]
    end
  end

  describe "multilingual support" do
    it "works with Japanese Wikipedia" do
      f = described_class.new("ja", "日本の都市")

      stub_request(:get, /ja\.wikipedia\.org/)
        .to_return(
          status: 200,
          body: { query: { categorymembers: [{ ns: 0, title: "東京" }] } }.to_json
        )

      expect(f.fetch_articles).to eq ["東京"]
    end

    it "works with German Wikipedia" do
      f = described_class.new("de", "Stadt in Deutschland")

      stub_request(:get, /de\.wikipedia\.org/)
        .to_return(
          status: 200,
          body: { query: { categorymembers: [{ ns: 0, title: "Berlin" }] } }.to_json
        )

      expect(f.fetch_articles).to eq ["Berlin"]
    end
  end
end
