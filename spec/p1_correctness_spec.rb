# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "timeout"
require "open3"
require "rake"
require_relative "../lib/wp2txt/stream_processor"
require_relative "../lib/wp2txt/corpus"
require_relative "../lib/wp2txt/corpus_jobs"
require_relative "../lib/wp2txt/output_path"
require_relative "support/multistream_fixture"

RSpec.describe "P1 correctness contracts" do
  include MultistreamFixture

  around do |example|
    Dir.mktmpdir("wp2txt-p1-") do |dir|
      @dir = dir
      example.run
    end
  end

  def processor_for(bytes, size)
    processor = Wp2txt::StreamProcessor.new("unused.xml", adaptive_buffer: false)
    processor.instance_variable_set(:@file_pointer, StringIO.new(bytes.b))
    processor.instance_variable_set(:@buffer_size, size)
    processor
  end

  describe "stream decoding" do
    %w[é あ 😀].each do |character|
      (1...character.bytesize).each do |boundary|
        it "preserves #{character.inspect} split after byte #{boundary}" do
          bytes = "x" * (8 - boundary) + character + "終"
          processor = processor_for(bytes, 8)
          nil while processor.send(:fill_buffer)
          expect(processor.instance_variable_get(:@buffer)).to eq(bytes)
        end
      end
    end

    it "scrubs invalid bytes and incomplete EOF without losing adjacent valid text" do
      processor = processor_for("é\xFFあ😀\xE3\x81".b, 1)
      nil while processor.send(:fill_buffer)
      expect(processor.instance_variable_get(:@buffer)).to eq("éあ😀")
    end

    it "handles empty input" do
      processor = processor_for("", 1)
      expect(processor.send(:fill_buffer)).to be false
      expect(processor.instance_variable_get(:@buffer)).to eq("")
    end

    it "preserves multibyte XML content through one-byte reads" do
      path = File.join(@dir, "boundary.xml")
      File.binwrite(path, page_xml(id: 1, ns: 0, title: "作品: é😀", text: "あé😀"))
      processor = Wp2txt::StreamProcessor.new(path, adaptive_buffer: false)
      processor.instance_variable_set(:@buffer_size, 1)
      expect(processor.each_page.to_a).to eq([["作品: é😀", "あé😀"]])
    end
  end

  describe "namespace parity" do
    [["作品: 東京", 0, true], ["No punctuation", 4, false], ["", 6, false]].each do |title, ns, included|
      it "uses ns=#{ns} for #{title.inspect}" do
        xml = page_xml(id: 1, ns: ns, title: title, text: "日本語")
        processor = Wp2txt::StreamProcessor.new("unused.xml", adaptive_buffer: false)
        expect(!processor.send(:parse_page_xml, xml).nil?).to eq(included)
        rows = { pages: [], categories: [], sections: [], hierarchy: [] }
        Wp2txt::MetadataIndexBuilder.scan_page(xml, rows)
        expect(rows[:pages].first[2]).to eq(ns) unless title.empty?
      end
    end

    it "uses namespace elements in the turbo extraction and section-stat paths" do
      input = File.join(@dir, "pages.xml")
      output = File.join(@dir, "output.jsonl")
      File.write(input, [
        page_xml(id: 1, ns: 0, title: "作品: 東京", text: "本文\n== Allowed ==\nあ"),
        page_xml(id: 2, ns: 4, title: "No punctuation", text: "本文\n== Hidden ==\nあ"),
        page_xml(id: 3, ns: 0, title: "Empty", text: "")
      ].join)
      script = <<~'CODE'
        path, input, output = ARGV
        source = File.read(path).split("\n# Handle Ctrl+C gracefully").first
        eval(source, TOPLEVEL_BINDING, path)
        require File.expand_path("../lib/wp2txt/corpus", File.dirname(path))
        app = WpApp.new
        count = app.send(:process_xml_file_and_write, input, output,
                         Wp2txt::Corpus::RENDER_CONFIG.merge(format: :json), false, :json)
        stats = app.send(:process_xml_file_for_stats, input)
        puts JSON.generate(count: count, stats: stats)
      CODE
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", script,
        File.expand_path("../bin/wp2txt", __dir__), input, output)
      expect(status.success?).to be(true), stderr
      result = JSON.parse(stdout)
      expect(result["count"]).to eq(1)
      expect(result["stats"].to_json).to include("Allowed")
      expect(result["stats"].to_json).not_to include("Hidden")
      expect(File.read(output)).to include("作品: 東京")
    end

    it "retains the historical ns=0 default for missing ns in both parsers" do
      xml = page_xml(id: 1, ns: 0, title: "作品: 東京", text: "本文").sub(/<ns>.*?<\/ns>/, "")
      processor = Wp2txt::StreamProcessor.new("unused.xml", adaptive_buffer: false)
      expect(processor.send(:parse_page_xml, xml)).to eq(["作品: 東京", "本文"])
      rows = { pages: [], categories: [], sections: [], hierarchy: [] }
      Wp2txt::MetadataIndexBuilder.scan_page(xml, rows)
      expect(rows[:pages].first[2]).to eq(0)
    end
  end

  describe "SQL rows and cells" do
    around do |example|
      @corpus = Wp2txt::Corpus.allocate
      @db = SQLite3::Database.new(":memory:")
      example.run
    ensure
      @db.close
    end

    it "reserves original and generated column names without losing values" do
      path = File.join(@dir, "q.jsonl")
      result = @corpus.send(:run_sql_file_on, @db,
                            'SELECT 1 AS x, 2 AS x, 3 AS x_2, 4 AS x, 5 AS "日本", 6 AS "日本", 7 AS ""', path)
      record = JSON.parse(File.read(path))
      expect(record).to eq("x" => 1, "x_3" => 2, "x_2" => 3, "x_4" => 4,
                           "日本" => 5, "日本_2" => 6, "" => 7)
      expect(result[:column_mapping][1]).to eq(ordinal: 1, original_name: "x", output_name: "x_3")
    end

    [0, 1, 2].each do |rows|
      it "reports truncation only when more than the limit exists (#{rows} rows)" do
        result = @corpus.send(:run_sql_on, @db, "SELECT 1 UNION ALL SELECT 2 LIMIT #{rows}", 1)
        expect(result[:truncated]).to eq(rows > 1)
        expect(result[:row_count]).to eq([rows, 1].min)
      end
    end

    it "does not silently sanitize invalid UTF-8 cells while clipping" do
      @db.execute("CREATE TABLE cells (value BLOB)")
      @db.execute("INSERT INTO cells VALUES (?)", [SQLite3::Blob.new("\xFF".b + "a" * 70_000)])
      expect do
        @corpus.send(:run_sql_file_on, @db, "SELECT value FROM cells", File.join(@dir, "invalid.jsonl"))
      end.to raise_error(JSON::GeneratorError)
    end

    it "clips by bytes including the ellipsis without splitting UTF-8" do
      @db.execute("CREATE TABLE cells (value TEXT)")
      values = ["あ" * 30_000, "😀" * 20_000, "é" * 40_000, "", "a" * 65_536]
      values.each { |value| @db.execute("INSERT INTO cells VALUES (?)", [value]) }
      path = File.join(@dir, "cells.jsonl")
      result = @corpus.send(:run_sql_file_on, @db, "SELECT value FROM cells", path)
      output = File.readlines(path).map { |line| JSON.parse(line)["value"] }
      expect(result[:cells_clipped]).to eq(3)
      expect(output.all?(&:valid_encoding?)).to be true
      expect(output.map(&:bytesize).max).to be <= 65_536
      expect(output.first(3).all? { |value| value.end_with?("…") }).to be true
      expect(output.last(2)).to eq(values.last(2))
    end
  end

  describe "exclusive staged output" do
    let(:out) { File.join(@dir, "成果.jsonl") }

    def publish(path, overwrite: false)
      Wp2txt::OutputPath.write_pair(path, overwrite: overwrite) do |data, meta|
        File.write(data, "本文")
        File.write(meta, "{}")
      end
    end

    it "rejects symlink directories, output files, dangling links, and sidecars even with overwrite" do
      target = File.join(@dir, "target")
      Dir.mkdir(target)
      link = File.join(@dir, "link")
      File.symlink(target, link)
      expect { publish(File.join(link, "out"), overwrite: true) }.to raise_error(ArgumentError, /symbolic/)
      [out, "#{out}.meta.json"].each do |destination|
        File.symlink(File.join(target, "missing"), destination)
        expect { publish(out, overwrite: true) }.to raise_error(ArgumentError, /symbolic/)
        expect { Wp2txt::OutputPath.confine(out, @dir, overwrite: true) }.to raise_error(ArgumentError, /symbolic/)
        File.unlink(destination)
      end
      expect(Dir.children(target)).to be_empty
    end

    it "rejects an existing sidecar without creating the output" do
      File.write("#{out}.meta.json", "old")
      expect { publish(out) }.to raise_error(ArgumentError, /already exists/)
      expect(File.exist?(out)).to be false
      expect(File.read("#{out}.meta.json")).to eq("old")
    end

    it "uses EXCL even if a file arrives after validation" do
      allow(Wp2txt::OutputPath).to receive(:validate_pair!).and_wrap_original do |method, *args, **kwargs|
        method.call(*args, **kwargs)
        File.write(out, "competing writer")
      end
      expect { publish(out) }.to raise_error(ArgumentError, /already exists/)
      expect(File.read(out)).to eq("competing writer")
      expect(File.exist?("#{out}.meta.json")).to be false
    end

    it "cleans its own reservation when sidecar reservation loses a race" do
      allow(Wp2txt::OutputPath).to receive(:validate_pair!).and_wrap_original do |method, *args, **kwargs|
        method.call(*args, **kwargs)
        File.write("#{out}.meta.json", "competing writer")
      end
      expect { publish(out) }.to raise_error(ArgumentError, /already exists/)
      expect(File.exist?(out)).to be false
      expect(File.read("#{out}.meta.json")).to eq("competing writer")
    end

    it "publishes both files and leaves no temporary files" do
      publish(out)
      expect(File.read(out)).to eq("本文")
      expect(File.read("#{out}.meta.json")).to eq("{}")
      expect(Dir.children(@dir).sort).to eq([File.basename(out), File.basename(out) + ".meta.json"].sort)
    end

    it "preserves old files if staging fails during an overwrite" do
      File.write(out, "old data")
      File.write("#{out}.meta.json", "old meta")
      expect do
        Wp2txt::OutputPath.write_pair(out, overwrite: true) do |data, _meta|
          File.write(data, "incomplete")
          raise "failed"
        end
      end.to raise_error("failed")
      expect(File.read(out)).to eq("old data")
      expect(File.read("#{out}.meta.json")).to eq("old meta")
      expect(Dir.glob(File.join(@dir, ".wp2txt-*"))).to be_empty
      publish(out, overwrite: true)
      expect(File.read(out)).to eq("本文")
    end

    it "allows only one concurrent writer without overwrite" do
      entered = Queue.new
      release = Queue.new
      writer = Thread.new do
        Wp2txt::OutputPath.write_pair(out) do |data, meta|
          entered << true
          release.pop
          File.write(data, "first")
          File.write(meta, "{}")
        end
      end
      Timeout.timeout(3) { entered.pop }
      expect { publish(out) }.to raise_error(ArgumentError, /already exists/)
      release << true
      writer.value
      expect(File.read(out)).to eq("first")
    ensure
      release << true
      writer&.join
    end
  end

  describe "Parallel finish contract" do
    [0, 2].each do |workers|
      it "delivers each payload to finish but retains none with #{workers} workers" do
        skip "fork unavailable" if workers.positive? && !Process.respond_to?(:fork)
        payloads = ["日本語", "\xFF".b, ""]
        received = []
        returned = Parallel.each(payloads, in_processes: workers,
                                 finish: ->(_item, _i, value) { received << value }) { |value| "rendered:#{value.bytesize}" }
        expect(received).to match_array(payloads.map { |value| "rendered:#{value.bytesize}" })
        expect(Array(returned).flatten.grep(/\Arendered:/)).to be_empty
      end
    end

    it "builds both indexes while disabling retained batch results" do
      dump, index_path = create_fixture(@dir)
      index = Wp2txt::MultistreamIndex.new(index_path, use_cache: false, show_progress: false)
      calls = []
      allow(Parallel).to receive(:each).and_wrap_original do |method, source, options, &block|
        calls << options
        method.call(source, options, &block)
      end
      meta_path = Wp2txt::MetadataIndex.path_for(dump, cache_dir: @dir)
      meta = Wp2txt::MetadataIndexBuilder.new(dump, index.stream_offsets, db_path: meta_path, num_processes: 0).build
      expect(meta.stats[:article_count]).to eq(3)
      meta.close
      fts = Wp2txt::FtsIndexBuilder.new(dump, index.stream_offsets,
        db_path: File.join(@dir, "fts.sqlite3"), meta_db_path: meta_path, num_processes: 0).build
      expect(fts.search("Story", count: "exact")[:total]).to eq(2)
      expect(calls.size).to eq(2)
      expect(calls.all? { |options| options[:finish] && !options.key?(:preserve_results) }).to be true
      fts.close
    end
  end

  describe "job lifecycle" do
    it "records factory failure and permits a subsequent job" do
      manager = Wp2txt::CorpusJobManager.new(-> { raise "factory failure" })
      first = manager.start_extract({})
      Timeout.timeout(3) { Thread.pass until manager.status(first[:job_id])[:status] == "error" }
      expect(manager.status(first[:job_id])[:error]).to include("factory failure")
      second = manager.start_extract({})
      expect(second[:job_id]).not_to eq(first[:job_id])
      Timeout.timeout(3) { Thread.pass until manager.status(second[:job_id])[:status] == "error" }
    end

    it "atomically admits one job from simultaneous callers" do
      release = Queue.new
      fake = Object.new
      fake.define_singleton_method(:extract_corpus) { |**_params| release.pop; {} }
      fake.define_singleton_method(:close) {}
      manager = Wp2txt::CorpusJobManager.new(-> { fake })
      # Yield during state construction, precisely where the old implementation
      # had released its check lock but had not registered the running job.
      allow(Time).to receive(:now).and_wrap_original do |method|
        sleep 0.005
        method.call
      end
      gate = Queue.new
      callers = Array.new(12) { Thread.new { gate.pop; manager.start_extract({}) } }
      12.times { gate << true }
      results = callers.map(&:value)
      expect(results.count { |result| result[:job_id] }).to eq(1)
      expect(results.count { |result| result[:error] }).to eq(11)
      release << true
      Timeout.timeout(3) { Thread.pass until manager.list.first[:status] == "completed" }
    ensure
      release << true
      callers&.each(&:join)
    end
  end

  describe "image verification" do
    around do |example|
      previous = Rake.application
      Rake.application = Rake::Application.new
      Rake::Task.define_task(:build)
      suppress_stderr { load File.expand_path("../Rakefile", __dir__) }
      example.run
    ensure
      Rake.application = previous
    end

    [[false, "Cannot connect to daemon"], [false, "image missing"], [true, "LEAK:/wp2txt/tmp\n"]].each do |success, output|
      it "fails verification for #{output.strip}" do
        allow(Open3).to receive(:capture2e).and_return([output, double(success?: success)])
        expect { suppress_stderr { Rake::Task[:verify_image].invoke("test-image") } }.to raise_error(SystemExit)
      end
    end

    it "passes only after a successful clean container inspection" do
      expect(Open3).to receive(:capture2e).with("docker", "run", "--rm", "test-image", "sh", "-c", kind_of(String))
        .and_return(["", double(success?: true)])
      expect { Rake::Task[:verify_image].invoke("test-image") }.to output(/OK:/).to_stdout
    end
  end
end
