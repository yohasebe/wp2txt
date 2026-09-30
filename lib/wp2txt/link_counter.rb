# frozen_string_literal: true

require "parallel"
require "sqlite3"
require "time"
require_relative "metadata_index"
require_relative "version"
require_relative "text_processing"
require_relative "wikitext_regions"

module Wp2txt
  # Counts, for every article, how many other articles link to it, and stores
  # the result in the metadata index as page_inlinks(page_id, inlinks,
  # via_redirects).
  #
  # Rules (recorded as RULE_VERSION so counts from different rules are never
  # compared unknowingly):
  # - sources are articles (namespace 0) that are not redirects
  # - each source counts once per target, however many times it links there
  # - a link to a redirect counts for the redirect's target (one hop);
  #   via_redirects is how many sources reached the target only that way
  # - only links written in the article's own wikitext count; links that
  #   templates add when rendered (navigation boxes) are not in the dump text
  # - commented-out links do not count
  class LinkCounter
    include Wp2txt

    RULE_VERSION = "2"
    STREAMS_PER_BATCH = 50
    LINK_REGEX = /\[\[([^\[\]|<>{}\n]+)(?=\||\]\])/
    COMMENT_REGEX = /<!--.*?-->/m

    def initialize(multistream_path, stream_offsets, db_path:, num_processes: 4)
      @multistream_path = multistream_path
      @stream_offsets = stream_offsets
      @db_path = db_path
      @num_processes = num_processes
    end

    # @return [Hash] { articles:, with_inlinks:, rule_version: }
    def count!(&progress)
      titles, redirects = load_titles
      # Inherited by the forked workers (copy-on-write); they only read it
      @redirects = redirects

      direct = Hash.new(0)
      via = Hash.new(0)
      pairs = @stream_offsets.zip(@stream_offsets[1..].to_a + [nil])
      batches = pairs.each_slice(STREAMS_PER_BATCH).to_a
      done = 0

      Parallel.each(
        batches,
        in_processes: @num_processes,
        finish: lambda { |_item, _idx, result|
          result[:direct].each { |t, n| direct[t] += n }
          result[:via].each { |t, n| via[t] += n }
          done += 1
          progress&.call(done, batches.size)
        }
      ) do |batch|
        scan_batch(batch)
      end

      write(titles, direct, via)
    end

    private

    # Articles (title => page_id) and redirects (title => target title)
    def load_titles
      db = SQLite3::Database.new(@db_path, readonly: true)
      @case_rule = db.get_first_value("SELECT value FROM metadata WHERE key = 'case_rule'") || "first-letter"
      titles = {}
      redirects = {}
      db.execute("SELECT page_id, title, redirect_to FROM pages WHERE namespace = 0") do |id, title, target|
        if target
          redirects[title] = normalize_target(target)
        else
          titles[title] = id
        end
      end
      [titles, redirects]
    ensure
      db&.close
    end

    # Runs in a worker: returns per-target counts for this batch of streams
    def scan_batch(offset_pairs)
      direct = Hash.new(0)
      via = Hash.new(0)
      File.open(@multistream_path, "rb") do |f|
        offset_pairs.each do |offset, next_offset|
          f.seek(offset)
          data = next_offset ? f.read(next_offset - offset) : f.read
          xml = MetadataIndexBuilder.decompress_bz2(data)
          xml.scan(MetadataIndexBuilder::PAGE_BLOCK_REGEX) do
            count_page(::Regexp.last_match(1), direct, via)
          end
        end
      end
      { direct: direct, via: via }
    end

    def count_page(block, direct, via)
      return unless Wp2txt.namespace_id(block[MetadataIndexBuilder::NS_REGEX, 1]).zero?

      text = MetadataIndexBuilder.unescape_xml(block[MetadataIndexBuilder::TEXT_REGEX, 1] || "")
      return if Wp2txt::REDIRECT_REGEX.match?(text)

      reached = {} # target => true if reached directly at least once
      WikitextRegions.remove_literal(text).scan(LINK_REGEX) do |(raw)|
        name = normalize_target(raw)
        next if name.empty?

        if (target = @redirects[name])
          reached[target] ||= false
        else
          reached[name] = true
        end
      end
      reached.each do |target, directly|
        direct[target] += 1
        via[target] += 1 unless directly
      end
    end

    def normalize_target(raw)
      # Decode each reference in the original input, never references created
      # by decoding another one (special_chr has two decoding stages).
      decoded = raw.gsub(/&(?:#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]*);/) { |entity| special_chr(entity) }
      title = decoded.split("#", 2).first.to_s.strip.sub(/\A:/, "")
      MetadataIndex.normalize_title(title, case_rule: @case_rule || "first-letter")
    end

    def write(titles, direct, via)
      db = SQLite3::Database.new(@db_path)
      db.busy_timeout = 5000
      db.execute("DROP TABLE IF EXISTS page_inlinks")
      db.execute("DELETE FROM metadata WHERE key LIKE 'links\\_%' ESCAPE '\\'")
      db.execute(<<~SQL)
        CREATE TABLE page_inlinks (
          page_id       INTEGER PRIMARY KEY,
          inlinks       INTEGER NOT NULL,
          via_redirects INTEGER NOT NULL
        )
      SQL
      with_inlinks = 0
      db.transaction do
        stmt = db.prepare("INSERT INTO page_inlinks (page_id, inlinks, via_redirects) VALUES (?, ?, ?)")
        titles.each do |title, page_id|
          n = direct[title]
          with_inlinks += 1 if n.positive?
          stmt.execute([page_id, n, via[title]])
        end
        stmt.close
      end
      db.execute("CREATE INDEX idx_page_inlinks_count ON page_inlinks(inlinks)")
      {
        links_counted_at: Time.now.utc.iso8601,
        links_rule_version: RULE_VERSION,
        links_wp2txt_version: Wp2txt::VERSION,
        links_article_count: titles.size,
        links_with_inlinks: with_inlinks
      }.each { |k, v| db.execute("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)", [k.to_s, v.to_s]) }
      { articles: titles.size, with_inlinks: with_inlinks, rule_version: RULE_VERSION }
    ensure
      db&.close
    end
  end
end
