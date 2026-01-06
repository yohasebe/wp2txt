# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require "json"

RSpec.describe Wp2txt::OutputWriter do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#write" do
    context "with text format" do
      it "writes text content to file" do
        writer = described_class.new(
          output_dir: temp_dir,
          base_name: "output",
          format: :text,
          file_size_mb: 0
        )

        writer.write("Article 1 content\n")
        writer.write("Article 2 content\n")
        files = writer.close

        expect(files.size).to eq(1)
        content = File.read(files.first)
        expect(content).to include("Article 1 content")
        expect(content).to include("Article 2 content")
      end

      it "creates .txt extension" do
        writer = described_class.new(
          output_dir: temp_dir,
          base_name: "output",
          format: :text,
          file_size_mb: 0
        )

        writer.write("content")
        files = writer.close

        expect(files.first).to end_with(".txt")
      end
    end

    context "with JSON format" do
      it "writes JSON content to file" do
        writer = described_class.new(
          output_dir: temp_dir,
          base_name: "output",
          format: :json,
          file_size_mb: 0
        )

        writer.write({ title: "Article 1", text: "Content 1" })
        writer.write({ title: "Article 2", text: "Content 2" })
        files = writer.close

        expect(files.size).to eq(1)
        lines = File.readlines(files.first)
        expect(lines.size).to eq(2)

        json1 = JSON.parse(lines[0])
        expect(json1["title"]).to eq("Article 1")

        json2 = JSON.parse(lines[1])
        expect(json2["title"]).to eq("Article 2")
      end

      it "creates .jsonl extension" do
        writer = described_class.new(
          output_dir: temp_dir,
          base_name: "output",
          format: :json,
          file_size_mb: 0
        )

        writer.write({ title: "Test" })
        files = writer.close

        expect(files.first).to end_with(".jsonl")
      end
    end

    context "with file rotation" do
      it "rotates files based on size" do
        writer = described_class.new(
          output_dir: temp_dir,
          base_name: "output",
          format: :text,
          file_size_mb: 1  # 1 MB threshold
        )

        # Write content that exceeds 1 MB
        large_content = "x" * (512 * 1024)  # 512 KB each
        writer.write(large_content + "\n")
        writer.write(large_content + "\n")
        writer.write(large_content + "\n")  # This should trigger rotation
        files = writer.close

        expect(files.size).to be >= 2
      end

      it "uses indexed filenames when rotating" do
        writer = described_class.new(
          output_dir: temp_dir,
          base_name: "output",
          format: :text,
          file_size_mb: 1
        )

        large_content = "x" * (600 * 1024)
        writer.write(large_content + "\n")
        writer.write(large_content + "\n")
        writer.write(large_content + "\n")
        files = writer.close

        expect(files.any? { |f| f.include?("-1.") }).to be true
        expect(files.any? { |f| f.include?("-2.") }).to be true
      end
    end

    context "with empty content" do
      it "ignores nil content" do
        writer = described_class.new(
          output_dir: temp_dir,
          base_name: "output",
          format: :text,
          file_size_mb: 0
        )

        writer.write(nil)
        writer.write("valid content\n")
        files = writer.close

        content = File.read(files.first)
        expect(content).to eq("valid content\n")
      end

      it "ignores empty string content" do
        writer = described_class.new(
          output_dir: temp_dir,
          base_name: "output",
          format: :text,
          file_size_mb: 0
        )

        writer.write("")
        writer.write("   ")
        writer.write("valid content\n")
        files = writer.close

        content = File.read(files.first)
        expect(content).to eq("valid content\n")
      end
    end

    context "thread safety" do
      it "handles concurrent writes" do
        writer = described_class.new(
          output_dir: temp_dir,
          base_name: "output",
          format: :text,
          file_size_mb: 0
        )

        threads = 10.times.map do |i|
          Thread.new do
            10.times do |j|
              writer.write("Thread #{i} Line #{j}\n")
            end
          end
        end

        threads.each(&:join)
        files = writer.close

        content = File.read(files.first)
        lines = content.lines
        expect(lines.size).to eq(100)
      end
    end
  end

  describe "#close" do
    it "removes empty files" do
      writer = described_class.new(
        output_dir: temp_dir,
        base_name: "output",
        format: :text,
        file_size_mb: 0
      )

      # Don't write anything
      files = writer.close

      # Should have created then removed empty file
      expect(files).to be_empty
    end

    it "returns list of created files" do
      writer = described_class.new(
        output_dir: temp_dir,
        base_name: "output",
        format: :text,
        file_size_mb: 0
      )

      writer.write("content\n")
      files = writer.close

      expect(files).to be_an(Array)
      expect(files.size).to eq(1)
      expect(File.exist?(files.first)).to be true
    end
  end
end
