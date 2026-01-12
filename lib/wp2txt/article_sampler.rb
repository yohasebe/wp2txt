# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "fileutils"
require "openssl"

module Wp2txt
  # SSL-safe HTTP GET (duplicated from multistream.rb for standalone use)
  def self.ssl_safe_get(uri, timeout: 30)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = timeout
    http.read_timeout = timeout

    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.verify_callback = ->(_preverify_ok, _store_ctx) { true }
    end

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "wp2txt/2.0 (https://github.com/yohasebe/wp2txt)"
    http.request(request)
  end
  # Fetches random articles from Wikipedia API for benchmarking and testing
  # Retrieves both raw wikitext and MediaWiki-rendered plain text
  class ArticleSampler
    API_ENDPOINT = "https://%s.wikipedia.org/w/api.php"
    MAX_BATCH_SIZE = 50  # Wikipedia API limit for random articles

    attr_reader :lang, :output_dir

    def initialize(lang: "en", output_dir: nil)
      @lang = lang
      @output_dir = output_dir || File.join(Dir.pwd, "samples", lang)
      @api_url = format(API_ENDPOINT, lang)
    end

    # Fetch N random articles with both wikitext and rendered text
    # @param count [Integer] Number of articles to fetch
    # @param progress [Boolean] Show progress indicator
    # @return [Array<Hash>] Array of article data
    def fetch_random_articles(count, progress: true)
      articles = []
      remaining = count

      while remaining > 0
        batch_size = [remaining, MAX_BATCH_SIZE].min
        titles = fetch_random_titles(batch_size)

        titles.each_with_index do |title, idx|
          print "\rFetching: #{articles.size + 1}/#{count} - #{title[0, 40]}..." if progress

          article = fetch_article(title)
          articles << article if article

          remaining -= 1
          break if remaining <= 0

          # Rate limiting - be nice to Wikipedia
          sleep 0.1
        end
      end

      puts "\nFetched #{articles.size} articles" if progress
      articles
    end

    # Fetch a single article by title
    # @param title [String] Article title
    # @return [Hash, nil] Article data or nil if failed
    def fetch_article(title)
      wikitext = fetch_wikitext(title)
      return nil unless wikitext

      rendered = fetch_rendered_text(title)
      return nil unless rendered

      {
        title: title,
        lang: @lang,
        wikitext: wikitext,
        rendered: rendered,
        fetched_at: Time.now.iso8601
      }
    end

    # Save fetched articles to disk
    # @param articles [Array<Hash>] Articles to save
    def save_articles(articles)
      FileUtils.mkdir_p(@output_dir)
      FileUtils.mkdir_p(File.join(@output_dir, "wikitext"))
      FileUtils.mkdir_p(File.join(@output_dir, "rendered"))

      metadata = []

      articles.each_with_index do |article, idx|
        safe_name = safe_filename(article[:title])

        # Save wikitext
        wikitext_path = File.join(@output_dir, "wikitext", "#{safe_name}.txt")
        File.write(wikitext_path, article[:wikitext])

        # Save rendered text
        rendered_path = File.join(@output_dir, "rendered", "#{safe_name}.txt")
        File.write(rendered_path, article[:rendered])

        metadata << {
          index: idx,
          title: article[:title],
          lang: article[:lang],
          wikitext_file: "wikitext/#{safe_name}.txt",
          rendered_file: "rendered/#{safe_name}.txt",
          wikitext_size: article[:wikitext].bytesize,
          rendered_size: article[:rendered].bytesize,
          fetched_at: article[:fetched_at]
        }
      end

      # Save metadata
      metadata_path = File.join(@output_dir, "articles.json")
      File.write(metadata_path, JSON.pretty_generate({
        lang: @lang,
        count: articles.size,
        generated_at: Time.now.iso8601,
        articles: metadata
      }))

      puts "Saved #{articles.size} articles to #{@output_dir}"
      metadata_path
    end

    # Convenience method: fetch and save in one call
    def sample(count, progress: true)
      articles = fetch_random_articles(count, progress: progress)
      save_articles(articles)
      articles
    end

    private

    # Fetch random article titles from Wikipedia API
    def fetch_random_titles(count)
      params = {
        action: "query",
        list: "random",
        rnnamespace: "0",  # Main namespace only
        rnlimit: count.to_s,
        format: "json"
      }

      response = api_request(params)
      return [] unless response

      response.dig("query", "random")&.map { |r| r["title"] } || []
    end

    # Fetch raw wikitext for an article
    def fetch_wikitext(title)
      params = {
        action: "query",
        titles: title,
        prop: "revisions",
        rvprop: "content",
        rvslots: "main",
        format: "json"
      }

      response = api_request(params)
      return nil unless response

      pages = response.dig("query", "pages")
      return nil unless pages

      page = pages.values.first
      return nil if page["missing"]

      page.dig("revisions", 0, "slots", "main", "*")
    end

    # Fetch MediaWiki-rendered plain text
    def fetch_rendered_text(title)
      params = {
        action: "query",
        titles: title,
        prop: "extracts",
        explaintext: "1",
        exsectionformat: "plain",
        format: "json"
      }

      response = api_request(params)
      return nil unless response

      pages = response.dig("query", "pages")
      return nil unless pages

      page = pages.values.first
      return nil if page["missing"]

      page["extract"]
    end

    # Make API request with error handling
    def api_request(params)
      uri = URI(@api_url)
      uri.query = URI.encode_www_form(params)

      response = Wp2txt.ssl_safe_get(uri, timeout: 30)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        warn "API request failed: #{response.code} #{response.message}"
        nil
      end
    rescue StandardError => e
      warn "API request error: #{e.message}"
      nil
    end

    # Convert title to safe filename
    def safe_filename(title)
      title
        .gsub(/[\/\\:*?"<>|]/, "_")
        .gsub(/\s+/, "_")
        .slice(0, 200)
    end
  end
end
