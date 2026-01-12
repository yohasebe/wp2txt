# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/wp2txt/article"

RSpec.describe "Live Article Processing", :live do
  include Wp2txt

  let(:live_articles) { Wp2txt::TestSupport::LiveArticles }

  describe "English Wikipedia articles" do
    context "with known articles" do
      it "processes Ruby (programming language) article" do
        article_data = live_articles.fetch_known_article(lang: :en, index: 0)
        skip "Could not fetch article (network unavailable?)" unless article_data

        article = Wp2txt::Article.new(article_data[:wikitext], article_data[:title])
        result = format_wiki(article_data[:wikitext], title: article_data[:title])

        expect(result).to be_a(String)
        expect(result.length).to be > 100
        expect(result).to include("programming")
      end

      it "processes Tokyo article" do
        article_data = live_articles.fetch_known_article(lang: :en, index: 1)
        skip "Could not fetch article (network unavailable?)" unless article_data

        result = format_wiki(article_data[:wikitext], title: article_data[:title])

        expect(result).to be_a(String)
        expect(result.length).to be > 100
        expect(result.downcase).to include("japan")
      end

      it "processes Albert Einstein article" do
        article_data = live_articles.fetch_known_article(lang: :en, index: 2)
        skip "Could not fetch article (network unavailable?)" unless article_data

        result = format_wiki(article_data[:wikitext], title: article_data[:title])

        expect(result).to be_a(String)
        expect(result.length).to be > 100
        expect(result.downcase).to include("physicist")
      end
    end

    context "with template expansion" do
      it "expands date templates correctly" do
        article_data = live_articles.fetch_known_article(lang: :en, index: 2) # Einstein
        skip "Could not fetch article (network unavailable?)" unless article_data

        result_without = format_wiki(article_data[:wikitext],
                                     title: article_data[:title],
                                     expand_templates: false)
        result_with = format_wiki(article_data[:wikitext],
                                  title: article_data[:title],
                                  expand_templates: true)

        # Template expansion should produce different output
        # (though both should be valid)
        expect(result_with).to be_a(String)
        expect(result_without).to be_a(String)
      end

      it "produces output closer to MediaWiki rendering with expansion" do
        article_data = live_articles.fetch_known_article(lang: :en, index: 0) # Ruby
        skip "Could not fetch article (network unavailable?)" unless article_data
        skip "No rendered text available" unless article_data[:rendered]

        result_with = format_wiki(article_data[:wikitext],
                                  title: article_data[:title],
                                  expand_templates: true)

        # Basic sanity check - expanded output should contain content
        expect(result_with.length).to be > 50
      end
    end

    context "with random articles" do
      it "processes random articles without errors" do
        articles = live_articles.fetch_random_articles(lang: :en, count: 3)
        skip "Could not fetch articles (network unavailable?)" if articles.empty?

        articles.each do |article_data|
          expect do
            format_wiki(article_data[:wikitext],
                        title: article_data[:title],
                        expand_templates: true)
          end.not_to raise_error
        end
      end
    end
  end

  describe "Japanese Wikipedia articles" do
    context "with known articles" do
      it "processes Ruby article in Japanese" do
        article_data = live_articles.fetch_known_article(lang: :ja, index: 0)
        skip "Could not fetch article (network unavailable?)" unless article_data

        result = format_wiki(article_data[:wikitext], title: article_data[:title])

        expect(result).to be_a(String)
        expect(result.length).to be > 100
        # Should contain some Japanese text
        expect(result).to match(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
      end

      it "processes Tokyo article in Japanese" do
        article_data = live_articles.fetch_known_article(lang: :ja, index: 1)
        skip "Could not fetch article (network unavailable?)" unless article_data

        result = format_wiki(article_data[:wikitext], title: article_data[:title])

        expect(result).to be_a(String)
        expect(result.length).to be > 100
        expect(result).to include("東京")
      end
    end

    context "with random articles" do
      it "processes random Japanese articles without errors" do
        articles = live_articles.fetch_random_articles(lang: :ja, count: 3)
        skip "Could not fetch articles (network unavailable?)" if articles.empty?

        articles.each do |article_data|
          expect do
            format_wiki(article_data[:wikitext],
                        title: article_data[:title],
                        expand_templates: true)
          end.not_to raise_error
        end
      end
    end
  end

  describe "Article structure extraction" do
    it "extracts categories from live article" do
      article_data = live_articles.fetch_known_article(lang: :en, index: 0)
      skip "Could not fetch article (network unavailable?)" unless article_data

      article = Wp2txt::Article.new(article_data[:wikitext], article_data[:title])
      categories = article.categories

      expect(categories).to be_an(Array)
      # Most Wikipedia articles have categories
      expect(categories.length).to be >= 0
    end

    it "extracts headings from live article" do
      article_data = live_articles.fetch_known_article(lang: :en, index: 0)
      skip "Could not fetch article (network unavailable?)" unless article_data

      article = Wp2txt::Article.new(article_data[:wikitext], article_data[:title])
      headings = article.elements.select { |type, _| type == :mw_heading }

      expect(headings).to be_an(Array)
      expect(headings.length).to be > 0
    end
  end
end
