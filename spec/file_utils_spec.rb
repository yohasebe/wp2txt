# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe "Wp2txt FileUtils" do
  include Wp2txt

  describe "collect_files" do
    let(:temp_dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(temp_dir) }

    it "collects all files in a directory" do
      # Create test files
      File.write(File.join(temp_dir, "file1.txt"), "content1")
      File.write(File.join(temp_dir, "file2.txt"), "content2")

      files = collect_files(temp_dir)
      expect(files).to include(a_string_ending_with("file1.txt"))
      expect(files).to include(a_string_ending_with("file2.txt"))
    end

    it "filters files by regex" do
      File.write(File.join(temp_dir, "file1.txt"), "content1")
      File.write(File.join(temp_dir, "file2.rb"), "content2")

      files = collect_files(temp_dir, /\.txt$/)
      expect(files).to include(a_string_ending_with("file1.txt"))
      expect(files).not_to include(a_string_ending_with("file2.rb"))
    end

    it "returns sorted list" do
      File.write(File.join(temp_dir, "z_file.txt"), "")
      File.write(File.join(temp_dir, "a_file.txt"), "")

      files = collect_files(temp_dir, /\.txt$/)
      txt_files = files.select { |f| f.end_with?(".txt") }
      expect(txt_files).to eq(txt_files.sort)
    end
  end

  describe "correct_separator" do
    it "converts backslashes to forward slashes on non-Windows" do
      skip "Only runs on non-Windows" if RUBY_PLATFORM.index("win32")
      expect(correct_separator("path\\to\\file")).to eq("path/to/file")
    end

    it "handles arrays of paths" do
      skip "Only runs on non-Windows" if RUBY_PLATFORM.index("win32")
      result = correct_separator(["path\\to\\file1", "path\\to\\file2"])
      expect(result).to eq(["path/to/file1", "path/to/file2"])
    end

    it "returns nil for nil input" do
      expect(correct_separator(nil)).to be_nil
    end
  end

  describe "sec_to_str" do
    it "converts seconds to HH:MM:SS format" do
      expect(sec_to_str(3661)).to eq("01:01:01")
    end

    it "handles zero" do
      expect(sec_to_str(0)).to eq("00:00:00")
    end

    it "handles large values" do
      expect(sec_to_str(86400)).to eq("24:00:00")  # 1 day
    end

    it "handles nil input" do
      expect(sec_to_str(nil)).to eq("--:--:--")
    end

    it "formats with leading zeros" do
      expect(sec_to_str(61)).to eq("00:01:01")
    end
  end

  describe "file_mod" do
    let(:temp_file) { Tempfile.new("test_file") }

    after do
      temp_file.close
      temp_file.unlink
      File.unlink("temp") if File.exist?("temp")
    end

    it "modifies file content using block" do
      temp_file.write("original content")
      temp_file.close

      file_mod(temp_file.path) do |content|
        content.upcase
      end

      expect(File.read(temp_file.path)).to eq("ORIGINAL CONTENT")
    end

    it "keeps backup when requested" do
      temp_file.write("original")
      temp_file.close

      file_mod(temp_file.path, true) do |content|
        "modified"
      end

      expect(File.exist?(temp_file.path + ".bak")).to be true
      File.unlink(temp_file.path + ".bak")
    end
  end

  describe "batch_file_mod" do
    let(:temp_dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(temp_dir) }

    it "yields each file in directory" do
      File.write(File.join(temp_dir, "file1.txt"), "")
      File.write(File.join(temp_dir, "file2.txt"), "")

      files_processed = []
      batch_file_mod(temp_dir) do |file|
        files_processed << File.basename(file)
      end

      expect(files_processed).to include("file1.txt", "file2.txt")
    end

    it "yields single file if path is a file" do
      file_path = File.join(temp_dir, "single.txt")
      File.write(file_path, "")

      files_processed = []
      batch_file_mod(file_path) do |file|
        files_processed << file
      end

      expect(files_processed).to eq([file_path])
    end
  end

  describe "rename" do
    let(:temp_dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(temp_dir) }

    it "renames files with extension" do
      file1 = File.join(temp_dir, "test-1")
      file2 = File.join(temp_dir, "test-2")
      File.write(file1, "")
      File.write(file2, "")

      rename([file1, file2], "txt")

      expect(File.exist?(File.join(temp_dir, "test-1.txt"))).to be true
      expect(File.exist?(File.join(temp_dir, "test-2.txt"))).to be true
    end

    it "returns true on success" do
      file1 = File.join(temp_dir, "test-1")
      File.write(file1, "")

      expect(rename([file1])).to be true
    end
  end
end
