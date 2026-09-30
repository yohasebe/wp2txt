# frozen_string_literal: true

require "spec_helper"
require "wp2txt/page_props_importer"
require "wp2txt/metadata_index"
require "wp2txt/corpus"
require "wp2txt/link_counter"
require "tmpdir"
require "open3"
require "json"
require "zlib"
require_relative "support/multistream_fixture"

RSpec.describe "page properties" do
  include MultistreamFixture
  TITLES = %w[東京 QID パイプ Sort Invalid Other Empty Absent].freeze
  FIELDS = %w[qid sort_key disambiguation].freeze

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      @dump = File.join(dir, "testwiki-20260101-pages-articles-multistream.xml.bz2")
      xml = TITLES.each_with_index.map { |t, i| page_xml(id: i + 1, ns: 0, title: t, text: "'''#{t}'''です。") }.join
      File.binwrite(@dump, bzip2("<mediawiki>\n#{xml}</mediawiki>"))
      File.write(@dump.sub(".xml.bz2", "-index.txt"), TITLES.each_with_index.map { |t, i| "0:#{i + 1}:#{t}\n" }.join)
      @db_path = Wp2txt::MetadataIndex.path_for(@dump, cache_dir: dir)
      Wp2txt::MetadataIndexBuilder.new(@dump, [0], db_path: @db_path, num_processes: 0).build.close
      @source = File.join(dir, "testwiki-20260101-page_props.sql.gz")
      @sql = <<~SQL
        INSERT INTO `page_props` VALUES
        (1,'defaultsort','とうきよう',NULL),
        (1,'disambiguation','ignored',NULL),
        (1,'wikibase_item','Q1490',NULL),
        (2,'wikibase_item','Q2',NULL),
        (3,'disambiguation','',NULL),
        (4,'defaultsort','O\\'Brien あ',NULL),
        (5,'defaultsort','\xFF\xFE',NULL),
        (6,'other','ignored',NULL),
        (7,'defaultsort','',NULL),
        (8,'wikibase_item','bad',NULL);
        INSERT INTO `other_table` VALUES (8,'wikibase_item','Q999',NULL);
      SQL
      Zlib::GzipWriter.open(@source) { |gz| gz.write(@sql.b) }
      example.run
    end
  end

  def import(**options)
    Wp2txt::PagePropsImporter.new(@db_path).import!(@source, **options)
  end

  def with_db
    db = SQLite3::Database.new(@db_path)
    yield db
  ensure
    db&.close
  end

  it "merges all three properties across batches and records counts and invalid sort keys" do
    stub_const("Wp2txt::PagePropsImporter::BATCH_SIZE", 1)
    result = import
    expect(result[:row_count]).to eq(5)
    with_db do |db|
      expect(db.execute("SELECT page_id,qid,disambiguation,sort_key FROM page_properties ORDER BY page_id"))
        .to eq([[1, "Q1490", 1, "とうきよう"], [2, "Q2", 0, nil], [3, nil, 1, nil],
                [4, nil, 0, "O'Brien あ"], [7, nil, 0, ""]])
    end
    expect(result[:provenance]).to include(page_count: 5, qid_count: 2, disambiguation_count: 2,
                                         sort_key_count: 3, skipped_invalid_sort_keys: 1,
                                         source_sha256: Digest::SHA256.file(@source).hexdigest)
    expect(import).to include(status: :already_imported, row_count: 5, provenance: result[:provenance])
  end

  it "replaces the unreleased QID table without requiring force" do
    with_db do |db|
      db.execute("CREATE TABLE page_qids (page_id INTEGER PRIMARY KEY, qid TEXT)")
      db.execute("INSERT INTO metadata VALUES ('page_props_imported_at','old')")
    end
    expect(import[:status]).to eq(:imported)
    with_db { |db| expect(db.get_first_value("SELECT 1 FROM sqlite_master WHERE name='page_qids'")).to be_nil }
  end

  def records(*flags)
    out = Dir.mktmpdir("out-", @dir)
    _, stderr, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../lib", __dir__),
                                      File.expand_path("../bin/wp2txt", __dir__), "-i", @dump,
                                      "--cache-dir", @dir, "--format", "json", "-n", "2", "-o", out, *flags)
    expect(status.success?).to be(true), stderr
    Dir[File.join(out, "*.jsonl")].flat_map { |f| File.readlines(f).map { |s| JSON.parse(s) } }.to_h { |r| [r["title"], r] }
  end

  it "always emits the three fields after import on both CLI paths, including null and false" do
    import
    turbo, stream = records, records("--no-turbo")
    expect(turbo.size).to eq(8)
    expect(turbo).to eq(stream)
    turbo.each_value { |r| expect(r.keys.first(6)).to eq(%w[title page_id revision_id qid sort_key disambiguation]) }
    expect(turbo["東京"].slice(*FIELDS)).to eq("qid" => "Q1490", "sort_key" => "とうきよう", "disambiguation" => true)
    expect(turbo["パイプ"].slice(*FIELDS)).to eq("qid" => nil, "sort_key" => nil, "disambiguation" => true)
    expect(turbo["Absent"].slice(*FIELDS)).to eq("qid" => nil, "sort_key" => nil, "disambiguation" => false)
    expect(turbo["Empty"]["sort_key"]).to eq("")
  end

  it "omits all three fields before import and after a failed force import" do
    [false, true].each do |fail_import|
      if fail_import
        import
        Zlib::GzipWriter.open(@source) { |gz| gz.write("-- empty\n") }
        expect { import(force: true) }.to raise_error(Wp2txt::Error, /no page_props rows/)
      end
      [[], ["--no-turbo"]].each do |flags|
        records(*flags).each_value { |r| expect(r.keys & FIELDS).to eq([]) }
      end
    end
  end

  it "attaches properties to Ractor JSON in the parent without omitting nulls" do
    import
    result = records("--no-turbo", "--ractor")
    expect(result["東京"].slice(*FIELDS)).to eq("qid" => "Q1490", "sort_key" => "とうきよう", "disambiguation" => true)
    expect(result["Absent"].slice(*FIELDS)).to eq("qid" => nil, "sort_key" => nil, "disambiguation" => false)
  end

  it "distinguishes an imported dump with no relevant properties from an unimported dump" do
    Zlib::GzipWriter.open(@source) { |gz| gz.write("INSERT INTO `page_props` VALUES (1,'other','',NULL);\n") }
    expect(import[:row_count]).to eq(0)
    expect(records["東京"].slice(*FIELDS)).to eq("qid" => nil, "sort_key" => nil, "disambiguation" => false)
  end

  it "applies the same contract to MCP's Corpus methods and provenance" do
    corpus = Wp2txt::Corpus.for_input(@dump, cache_dir: @dir)
    expect(corpus.get_article("東京").keys & FIELDS.map(&:to_sym)).to eq([])
    unimported = File.join(@dir, "unimported.jsonl")
    corpus.extract_corpus(output_path: unimported, titles: ["東京", "Absent"], content: "full", num_processes: 0)
    File.readlines(unimported).each { |line| expect(JSON.parse(line).keys & FIELDS).to eq([]) }
    corpus.close
    import
    corpus = Wp2txt::Corpus.for_input(@dump, cache_dir: @dir)
    expect(corpus.get_article("東京")).to include(qid: "Q1490", sort_key: "とうきよう", disambiguation: true)
    expect(corpus.get_article("Absent")).to include(qid: nil, sort_key: nil, disambiguation: false)
    output = File.join(@dir, "corpus.jsonl")
    corpus.extract_corpus(output_path: output, titles: ["東京", "パイプ", "Absent"], content: "full", num_processes: 0)
    rows = File.readlines(output).map { |s| JSON.parse(s) }
    expect(rows.size).to eq(3)
    rows.each { |r| expect(r.keys & FIELDS).to match_array(FIELDS) }
    expect(rows.last.slice(*FIELDS)).to eq("qid" => nil, "sort_key" => nil, "disambiguation" => false)
    expect(corpus.dump_info[:page_properties]).to include(qid_count: 2, disambiguation_count: 2, sort_key_count: 3,
                                                       skipped_invalid_sort_keys: 1)
  ensure
    corpus&.close
  end

  it "decodes title references once, including escaped ampersands and numeric references" do
    counter = Wp2txt::LinkCounter.new("", [], db_path: "")
    counter.instance_variable_set(:@redirects, {})
    direct, via = Hash.new(0), Hash.new(0)
    text = "[[A&amp;amp;B]] [[Caf&#233;]] [[東京&#35;節]] [[X&amp;lt;Y]]"
    counter.send(:count_page, page_xml(id: 1, ns: 0, title: "Source", text: text), direct, via)
    expect(direct).to eq("A&amp;B" => 1, "Café" => 1, "東京" => 1, "X&lt;Y" => 1)
  end
end
