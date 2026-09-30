# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"
require "tmpdir"
require "parallel"
require_relative "support/multistream_fixture"
require "wp2txt/multistream"
require "wp2txt/output_writer"
require "wp2txt/stream_processor"

RSpec.describe "output integrity" do
  include MultistreamFixture

  around do |example|
    Dir.mktmpdir("wp2txt-integrity-") do |dir|
      @dir = dir
      example.run
    end
  end

  let(:cli) { File.expand_path("../bin/wp2txt", __dir__) }
  let(:lib) { File.expand_path("../lib", __dir__) }

  def run_cli(*args)
    Open3.capture3(RbConfig.ruby, "-I", lib, cli, *args)
  end

  def json_records(dir)
    Dir[File.join(dir, "*")].flat_map { |f| File.readlines(f) }.map { |line| JSON.parse(line) }
  end

  def write_pages(path, count)
    body = (1..count).map { |i| page_xml(id: i, ns: 0, title: "記事#{i}", text: "本文#{i}。日本語の文。\n") }.join
    File.write(path, "<mediawiki>\n#{body}</mediawiki>\n")
  end

  describe "forked workers" do
    it "do not write the parent's buffered output again when they exit" do
      writer = Wp2txt::OutputWriter.new(output_dir: @dir, base_name: "out", format: :text, file_size_mb: 10)
      writer.write("one line still sitting in the buffer")
      writer.flush
      Parallel.map([1, 2, 3], in_processes: 3) { |x| x }
      files = writer.close
      expect(File.readlines(files.first).size).to eq(1)
    end

    it "leave every article exactly once in streaming output across batch boundaries" do
      input = File.join(@dir, "pages.xml")
      out = File.join(@dir, "out")
      Dir.mkdir(out)
      write_pages(input, 450) # batches of 200 with -n 2
      _stdout, stderr, status = run_cli("-i", input, "-o", out, "--format", "json", "-n", "2")
      expect(status.success?).to be(true), stderr

      titles = json_records(out).map { |r| r["title"] }
      expect(titles.size).to eq(450)
      expect(titles.tally.select { |_, n| n > 1 }).to be_empty
    end
  end

  describe "--num-procs" do
    it "uses the requested process count" do
      input = File.join(@dir, "pages.xml")
      out = File.join(@dir, "out")
      Dir.mkdir(out)
      write_pages(input, 3)
      stdout, stderr, status = run_cli("-i", input, "-o", out, "--format", "json", "-n", "1")
      expect(status.success?).to be(true), stderr
      expect(stdout.gsub(/\e\[[\d;]*m/, "")).to match(/CPU cores:\s*1\b/)
    end
  end

  describe "page and revision IDs" do
    it "appear in JSON records from the streaming path, including summaries" do
      input = File.join(@dir, "pages.xml")
      write_pages(input, 3)
      [[], ["--summary-only"]].each do |extra|
        out = File.join(@dir, "out#{extra.size}")
        Dir.mkdir(out)
        _stdout, stderr, status = run_cli("-i", input, "-o", out, "--format", "json", *extra)
        expect(status.success?).to be(true), stderr
        record = json_records(out).find { |r| r["title"] == "記事2" }
        expect(record).to include("page_id" => 2, "revision_id" => 200)
        expect(record.keys.first(3)).to eq(%w[title page_id revision_id])
      end
    end

    it "appear in JSON records from the default path for bz2 dumps" do
      dump, = create_fixture(@dir)
      out = File.join(@dir, "out")
      Dir.mkdir(out)
      _stdout, stderr, status = run_cli("-i", dump, "-o", out, "--format", "json")
      expect(status.success?).to be(true), stderr
      record = json_records(out).find { |r| r["title"] == "Film B" }
      expect(record).to include("page_id" => 2, "revision_id" => 200)
    end

    it "are read from the page header, not from the contributor" do
      xml = "<page><title>X</title><ns>0</ns><id>12</id><revision><id>34</id>" \
            "<contributor><id>9</id></contributor><text>t</text></revision></page>"
      expect(Wp2txt.page_ids(xml)).to eq(page_id: 12, revision_id: 34)
    end

    it "are offered by StreamProcessor only on request, keeping each_page's shape" do
      input = File.join(@dir, "pages.xml")
      write_pages(input, 1)
      processor = Wp2txt::StreamProcessor.new(input, adaptive_buffer: false)
      expect(processor.each_page.to_a).to eq([["記事1", "本文1。日本語の文。\n"]])
      with_ids = Wp2txt::StreamProcessor.new(input, adaptive_buffer: false).each_page(with_ids: true).to_a
      expect(with_ids.first.last).to eq(page_id: 1, revision_id: 100)
    end
  end

  describe "targeted extraction after an early index stop" do
    it "knows where the last found article's stream ends" do
      _dump, index_path = create_fixture(@dir)
      index = Wp2txt::MultistreamIndex.new(index_path, use_cache: false, target_titles: ["Film A"],
                                                       show_progress: false)
      expect(index.early_terminated?).to be(true)
      expect(index.stream_offsets).to eq([0])
      second_stream = File.readlines(index_path).map { |line| line.split(":").first.to_i }.uniq[1]
      expect(index.stream_end_offset).to eq(second_stream)
    end

    it "reads only that stream" do
      dump, index_path = create_fixture(@dir)
      index = Wp2txt::MultistreamIndex.new(index_path, use_cache: false, target_titles: ["Film A"],
                                                       show_progress: false)
      reader = Wp2txt::MultistreamReader.new(dump, index)
      stub_const("Wp2txt::MultistreamReader::MAX_TAIL_STREAM_BYTES", 0)
      expect(reader.extract_article("Film A")).to include(title: "Film A", id: 1, revision_id: 100)
    end

    it "refuses to read a large remainder in one call when the end is unknown" do
      dump, index_path = create_fixture(@dir)
      index = Wp2txt::MultistreamIndex.new(index_path, use_cache: false, target_titles: ["Film A"],
                                                       show_progress: false)
      index.instance_variable_set(:@stream_end_offset, nil)
      reader = Wp2txt::MultistreamReader.new(dump, index)
      stub_const("Wp2txt::MultistreamReader::MAX_TAIL_STREAM_BYTES", 0)
      expect { reader.extract_article("Film A") }.to raise_error(Wp2txt::Error, /cannot locate the end/)
    end
  end
end
