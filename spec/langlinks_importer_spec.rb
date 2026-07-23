# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "zlib"
require_relative "support/multistream_fixture"
require_relative "support/meta_db_fixture"
require_relative "../lib/wp2txt/langlinks_importer"
require_relative "../lib/wp2txt/multistream"

RSpec.describe Wp2txt::LanglinksImporter do
  include MultistreamFixture
  include MetaDbFixture

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      @multistream_path, @index_path = create_fixture(dir)

      ms_index = Wp2txt::MultistreamIndex.new(@index_path, use_cache: false, show_progress: false)
      @db_path = Wp2txt::MetadataIndex.path_for(@multistream_path, cache_dir: dir)
      Wp2txt::MetadataIndexBuilder.new(
        @multistream_path, ms_index.stream_offsets,
        db_path: @db_path, num_processes: 0
      ).build
      example.run
    end
  end

  # MySQL dump content covering the tricky cases: escaped quotes/backslashes,
  # commas and parens inside titles, underscores, multiple INSERT statements,
  # and an INSERT for a different table (must be ignored)
  LANGLINKS_SQL = <<~SQL
    -- MySQL dump fixture
    CREATE TABLE `langlinks` (
      `ll_from` int unsigned NOT NULL DEFAULT 0,
      `ll_lang` varbinary(20) NOT NULL DEFAULT '',
      `ll_title` varbinary(255) NOT NULL DEFAULT ''
    ) ENGINE=InnoDB DEFAULT CHARSET=binary;

    INSERT INTO `langlinks` VALUES (1,'en','Film A'),(1,'de','Film A (Film)'),(2,'en','It\\'s a Film, Really (1984)');
    INSERT INTO `langlinks` VALUES (3,'en','Back\\\\slash Title'),(3,'fr','Film B'),(4,'en','Underscore_title');
    INSERT INTO `pagelinks` VALUES (1,'Foo',0);
    UNLOCK TABLES;
  SQL

  def write_langlinks(name, content = LANGLINKS_SQL, gzip: false)
    path = File.join(@dir, name)
    if gzip
      Zlib::GzipWriter.open(path) { |gz| gz.write(content) }
    else
      File.write(path, content)
    end
    path
  end

  def import(path, **opts)
    described_class.new(@db_path, cache_dir: @dir).import!(path, **opts)
  end

  def langlinks_rows
    db = SQLite3::Database.new(@db_path, readonly: true)
    rows = db.execute("SELECT ll_from, ll_lang, ll_title FROM langlinks ORDER BY ll_from, ll_lang")
    db.close
    rows
  end

  describe "parsing and normalization" do
    it "imports tuples with escapes, commas, parens, and multiple INSERT statements" do
      path = write_langlinks("testwiki-20260101-langlinks.sql")
      result = import(path)

      expect(result[:status]).to eq(:imported)
      expect(result[:row_count]).to eq(6)
      expect(langlinks_rows).to contain_exactly(
        [1, "en", "Film A"],
        [1, "de", "Film A (Film)"],
        [2, "en", "It's a Film, Really (1984)"],
        [3, "en", 'Back\slash Title'],
        [3, "fr", "Film B"],
        [4, "en", "Underscore title"]
      )
    end

    it "reads .sql.gz files" do
      path = write_langlinks("testwiki-20260101-langlinks.sql.gz", gzip: true)
      expect(import(path)[:row_count]).to eq(6)
    end

    it "creates both indexes after the load" do
      path = write_langlinks("testwiki-20260101-langlinks.sql")
      import(path)
      db = SQLite3::Database.new(@db_path, readonly: true)
      indexes = db.execute("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'langlinks'").flatten
      db.close
      expect(indexes).to contain_exactly("idx_langlinks_from", "idx_langlinks_lang_title")
    end

    it "keeps all rows across batch boundaries" do
      stub_const("Wp2txt::LanglinksImporter::BATCH_SIZE", 2)
      path = write_langlinks("testwiki-20260101-langlinks.sql")
      expect(import(path)[:row_count]).to eq(6)
      expect(langlinks_rows.size).to eq(6)
    end

    it "imports multibyte (ja/zh/ko) titles, including escapes and underscores" do
      sql = <<~SQL
        INSERT INTO `langlinks` VALUES (1,'ja','宇宙戦艦ヤマト'),(2,'zh','粵語標題（電影）'),(3,'ko','한국어_제목'),(4,'ja','It\\'s 映画, Really（1984）');
      SQL
      path = write_langlinks("testwiki-20260101-langlinks.sql", sql)
      result = import(path)

      expect(result[:row_count]).to eq(4)
      expect(langlinks_rows).to contain_exactly(
        [1, "ja", "宇宙戦艦ヤマト"],
        [2, "zh", "粵語標題（電影）"],
        [3, "ko", "한국어 제목"],
        [4, "ja", "It's 映画, Really（1984）"]
      )
    end

    it "parses large multibyte INSERT lines fast enough (performance regression)" do
      # A single ~200KB+ extended INSERT line full of multibyte titles: the
      # old character-index parser was O(n²) here (minutes), regex scan is O(n)
      titles = ["宇宙戦艦ヤマト（映画）", "粵語標題（電影, 1984）", "한국어 제목", "時間の旅, それから"]
      tuples = Array.new(6_000) { |i| "(#{i + 1},'ja','#{titles[i % titles.size]}')" }
      sql = +"INSERT INTO `langlinks` VALUES " << tuples.join(",") << ";\n"
      expect(sql.bytesize).to be > 200_000

      path = write_langlinks("testwiki-20260101-langlinks.sql", sql)
      importer = described_class.new(@db_path, cache_dir: @dir)
      count = 0
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      importer.send(:each_source_row, path) { count += 1 }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      expect(count).to eq(6_000)
      expect(elapsed).to be < 0.5
    end

    it "filters target languages with the langs option" do
      path = write_langlinks("testwiki-20260101-langlinks.sql")
      result = import(path, langs: %w[en fr])

      expect(result[:row_count]).to eq(5)
      expect(langlinks_rows.map { |r| r[1] }.uniq).to contain_exactly("en", "fr")
      expect(result[:provenance][:lang_filter]).to eq("en,fr")
    end
  end

  describe "version pinning" do
    it "rejects a langlinks file whose dump name differs from the metadata DB" do
      path = write_langlinks("testwiki-20260102-langlinks.sql")
      expect { import(path) }.to raise_error(ArgumentError, /version mismatch/)
    end

    it "rejects a mismatched file even with force (no override)" do
      path = write_langlinks("testwiki-20260102-langlinks.sql")
      expect { import(path, force: true) }.to raise_error(ArgumentError, /version mismatch/)
    end

    it "rejects files whose name carries no dump name" do
      path = write_langlinks("langlinks.sql")
      expect { import(path) }.to raise_error(ArgumentError, /version mismatch/)
    end
  end

  describe "re-import" do
    it "is a no-op when already imported (reports imported_at)" do
      path = write_langlinks("testwiki-20260101-langlinks.sql")
      first = import(path)
      second = import(path)

      expect(second[:status]).to eq(:already_imported)
      expect(second[:imported_at]).to eq(first[:provenance][:imported_at])
      expect(second[:row_count]).to eq(6)
    end

    it "drops and re-imports with force, refreshing the provenance" do
      path = write_langlinks("testwiki-20260101-langlinks.sql")
      import(path)

      smaller = <<~SQL
        INSERT INTO `langlinks` VALUES (1,'en','Film A');
      SQL
      path2 = write_langlinks("testwiki-20260101-langlinks.sql", smaller)
      result = import(path2, force: true)

      expect(result[:status]).to eq(:imported)
      expect(result[:row_count]).to eq(1)
      expect(langlinks_rows).to eq([[1, "en", "Film A"]])
      expect(result[:provenance][:row_count]).to eq(1)
    end

    it "clears stale provenance when a forced re-import fails midway" do
      path = write_langlinks("testwiki-20260101-langlinks.sql")
      expect(import(path)[:status]).to eq(:imported)

      # Simulate a failure during the load (corrupt bytes, disk full, ...),
      # after the first batch has already been committed
      stub_const("Wp2txt::LanglinksImporter::BATCH_SIZE", 1)
      failing = described_class.new(@db_path, cache_dir: @dir)
      allow(failing).to receive(:each_source_row) do |_source, &block|
        block.call(1, "en", "Film A")
        raise IOError, "simulated read failure"
      end
      expect { failing.import!(path, force: true) }.to raise_error(IOError)

      # Partial table, but provenance is gone: judged as "not imported"
      expect(langlinks_rows).to eq([[1, "en", "Film A"]])
      meta = Wp2txt::MetadataIndex.new(@db_path)
      expect(meta.langlinks_provenance).to be_nil
      meta.close

      # A non-force retry re-imports instead of reporting a stale success
      retry_result = import(path)
      expect(retry_result[:status]).to eq(:imported)
      expect(retry_result[:row_count]).to eq(6)
    end
  end

  describe "provenance" do
    it "stamps source, size, time, tool version, filter, and row count" do
      path = write_langlinks("testwiki-20260101-langlinks.sql")
      prov = import(path)[:provenance]

      expect(prov[:source]).to eq("testwiki-20260101-langlinks.sql")
      expect(prov[:source_size]).to eq(File.size(path))
      expect(prov[:imported_at]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(prov[:imported_with]).to eq(Wp2txt::VERSION)
      expect(prov[:lang_filter]).to eq("all")
      expect(prov[:row_count]).to eq(6)

      meta = Wp2txt::MetadataIndex.new(@db_path)
      expect(meta.langlinks_provenance[:row_count]).to eq(6)
      meta.close
    end
  end

  describe "sanity check" do
    it "is skipped when the target language has no local meta DB" do
      path = write_langlinks("testwiki-20260101-langlinks.sql")
      expect(import(path)[:sanity]).to eq([])
    end

    it "reports the join rate against an installed target meta DB" do
      create_meta_db(@dir, lang: "en", date: "20260101",
                     pages: [[101, "Film A", 0, nil, 10], [102, "Film B", 0, nil, 10]])
      sql = <<~SQL
        INSERT INTO `langlinks` VALUES (1,'en','Film A'),(2,'en','Film B');
      SQL
      path = write_langlinks("testwiki-20260101-langlinks.sql", sql)
      result = import(path)

      expect(result[:sanity].size).to eq(1)
      check = result[:sanity].first
      expect(check[:lang]).to eq("en")
      expect(check[:match_rate]).to eq(1.0)
      expect(check[:warning]).to be false
      expect(check[:against]).to eq("enwiki-20260101")
    end

    it "warns when the join rate falls below 90%" do
      create_meta_db(@dir, lang: "en", date: "20260101",
                     pages: [[101, "Something Else", 0, nil, 10]])
      sql = <<~SQL
        INSERT INTO `langlinks` VALUES (1,'en','Film A'),(2,'en','Film B');
      SQL
      path = write_langlinks("testwiki-20260101-langlinks.sql", sql)
      check = import(path)[:sanity].first

      expect(check[:match_rate]).to eq(0.0)
      expect(check[:warning]).to be true
    end
  end
end
