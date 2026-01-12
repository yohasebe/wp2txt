# frozen_string_literal: true

require_relative "../../lib/wp2txt/article_sampler"

module Wp2txt
  module TestSupport
    # Live article fetching for integration tests
    # Uses Wikipedia API to get real articles, with caching for performance
    module LiveArticles
      CACHE_DIR = File.join(Dir.pwd, "tmp", "test_articles")
      CACHE_EXPIRY_DAYS = 7

      # Known articles for deterministic tests
      # These should be stable, well-formatted articles
      KNOWN_ARTICLES = {
        en: [
          "Ruby (programming language)",
          "Tokyo",
          "Albert Einstein",
          "World War II",
          "United States"
        ],
        ja: [
          "Ruby",
          "東京都",
          "アルベルト・アインシュタイン",
          "第二次世界大戦",
          "日本"
        ]
      }.freeze

      class << self
        # Fetch a known article by language and index
        # @param lang [Symbol] Language code (:en, :ja, etc.)
        # @param index [Integer] Index into KNOWN_ARTICLES array
        # @return [Hash] Article with :title, :wikitext, :rendered keys
        def fetch_known_article(lang: :en, index: 0)
          title = KNOWN_ARTICLES[lang][index]
          raise ArgumentError, "No known article at index #{index} for #{lang}" unless title

          fetch_article(lang: lang, title: title)
        end

        # Fetch a specific article by title
        # @param lang [Symbol] Language code
        # @param title [String] Article title
        # @return [Hash, nil] Article data or nil if not found
        def fetch_article(lang: :en, title:)
          cache_path = article_cache_path(lang, title)

          # Return from cache if fresh
          if cache_fresh?(cache_path)
            return load_from_cache(cache_path)
          end

          # Fetch from Wikipedia API
          sampler = ArticleSampler.new(lang: lang.to_s)
          article = sampler.fetch_article(title)
          return nil unless article

          # Cache the result
          save_to_cache(cache_path, article)
          article
        end

        # Fetch random articles for broader coverage tests
        # @param lang [Symbol] Language code
        # @param count [Integer] Number of articles to fetch
        # @return [Array<Hash>] Array of article data
        def fetch_random_articles(lang: :en, count: 5)
          cache_path = random_cache_path(lang, count)

          # Return from cache if fresh
          if cache_fresh?(cache_path)
            cached = load_from_cache(cache_path)
            return cached if cached.is_a?(Array) && cached.size >= count
          end

          # Fetch fresh random articles
          sampler = ArticleSampler.new(lang: lang.to_s)
          articles = sampler.fetch_random_articles(count, progress: false)

          # Cache the result
          save_to_cache(cache_path, articles)
          articles
        end

        # Check if cache exists and is fresh
        def cache_available?(lang: :en)
          KNOWN_ARTICLES[lang].any? do |title|
            cache_fresh?(article_cache_path(lang, title))
          end
        end

        # Clear all cached articles
        def clear_cache!
          FileUtils.rm_rf(CACHE_DIR)
        end

        # Warm up cache by fetching all known articles
        # Call this before running tests to ensure cache is populated
        def warm_cache!(lang: :en)
          puts "Warming cache for #{lang}..."
          KNOWN_ARTICLES[lang].each_with_index do |title, idx|
            print "  [#{idx + 1}/#{KNOWN_ARTICLES[lang].size}] #{title}..."
            article = fetch_article(lang: lang, title: title)
            puts article ? " OK" : " FAILED"
          end
        end

        private

        def article_cache_path(lang, title)
          safe_name = title.gsub(/[\/\\:*?"<>|]/, "_").gsub(/\s+/, "_")[0, 100]
          File.join(CACHE_DIR, lang.to_s, "articles", "#{safe_name}.json")
        end

        def random_cache_path(lang, count)
          File.join(CACHE_DIR, lang.to_s, "random", "sample_#{count}.json")
        end

        def cache_fresh?(path)
          return false unless File.exist?(path)

          age_days = (Time.now - File.mtime(path)) / (24 * 60 * 60)
          age_days < CACHE_EXPIRY_DAYS
        end

        def load_from_cache(path)
          JSON.parse(File.read(path), symbolize_names: true)
        rescue StandardError
          nil
        end

        def save_to_cache(path, data)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, JSON.pretty_generate(data))
        end
      end
    end
  end
end
