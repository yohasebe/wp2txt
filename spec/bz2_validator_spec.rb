# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require "wp2txt/bz2_validator"

RSpec.describe Wp2txt::Bz2Validator do
  let(:temp_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(temp_dir) }

  describe ".validate" do
    context "with non-existent file" do
      it "returns not_found error" do
        result = described_class.validate("/nonexistent/file.bz2")
        expect(result.valid?).to be false
        expect(result.error_type).to eq(:not_found)
      end
    end

    context "with too small file" do
      let(:small_file) { File.join(temp_dir, "small.bz2") }

      before { File.write(small_file, "BZh9") }

      it "returns too_small error" do
        result = described_class.validate(small_file)
        expect(result.valid?).to be false
        expect(result.error_type).to eq(:too_small)
      end
    end

    context "with invalid magic bytes" do
      let(:invalid_file) { File.join(temp_dir, "invalid.bz2") }

      before { File.write(invalid_file, "XX" + ("x" * 100)) }

      it "returns invalid_magic error" do
        result = described_class.validate(invalid_file)
        expect(result.valid?).to be false
        expect(result.error_type).to eq(:invalid_magic)
      end
    end

    context "with invalid version byte" do
      let(:invalid_version) { File.join(temp_dir, "bad_version.bz2") }

      before { File.write(invalid_version, "BZx9" + ("x" * 100)) }

      it "returns invalid_version error" do
        result = described_class.validate(invalid_version)
        expect(result.valid?).to be false
        expect(result.error_type).to eq(:invalid_version)
      end
    end

    context "with invalid block size" do
      let(:invalid_block) { File.join(temp_dir, "bad_block.bz2") }

      before { File.write(invalid_block, "BZh0" + ("x" * 100)) }

      it "returns invalid_block_size error" do
        result = described_class.validate(invalid_block)
        expect(result.valid?).to be false
        expect(result.error_type).to eq(:invalid_block_size)
      end
    end
  end

  describe ".validate_quick" do
    context "with valid header" do
      let(:valid_header_file) { File.join(temp_dir, "valid_header.bz2") }

      before { File.write(valid_header_file, "BZh9" + ("x" * 100)) }

      it "returns valid for correct header" do
        result = described_class.validate_quick(valid_header_file)
        expect(result.valid?).to be true
      end
    end

    context "with invalid header" do
      let(:invalid_file) { File.join(temp_dir, "invalid.bz2") }

      before { File.write(invalid_file, "XXXX" + ("x" * 100)) }

      it "returns invalid" do
        result = described_class.validate_quick(invalid_file)
        expect(result.valid?).to be false
      end
    end
  end

  describe ".validate_magic_bytes" do
    context "with valid bz2 header" do
      let(:valid_file) { File.join(temp_dir, "valid.bz2") }

      before { File.write(valid_file, "BZh9" + ("x" * 100)) }

      it "returns valid result" do
        result = described_class.validate_magic_bytes(valid_file)
        expect(result.valid?).to be true
        expect(result.details[:version]).to eq("h")
        expect(result.details[:block_size]).to eq(9)
      end
    end

    context "with different block sizes" do
      (1..9).each do |size|
        it "accepts block size #{size}" do
          file = File.join(temp_dir, "block#{size}.bz2")
          File.write(file, "BZh#{size}" + ("x" * 100))
          result = described_class.validate_magic_bytes(file)
          expect(result.valid?).to be true
        end
      end
    end
  end

  describe ".find_bzip2_command" do
    it "returns a string path or nil" do
      result = described_class.find_bzip2_command
      expect(result.nil? || result.is_a?(String)).to be true
    end
  end

  describe ".file_info" do
    context "with valid bz2 header" do
      let(:valid_file) { File.join(temp_dir, "info_test.bz2") }

      before { File.write(valid_file, "BZh5" + ("data" * 100)) }

      it "returns file information hash" do
        info = described_class.file_info(valid_file)
        expect(info).to be_a(Hash)
        expect(info[:path]).to eq(valid_file)
        expect(info[:size]).to be > 0
        expect(info[:valid_header]).to be true
        expect(info[:version]).to eq("h")
        expect(info[:block_size]).to eq(5)
        expect(info[:mtime]).to be_a(Time)
      end
    end

    context "with non-existent file" do
      it "returns nil" do
        info = described_class.file_info("/nonexistent/file.bz2")
        expect(info).to be_nil
      end
    end
  end

  describe "ValidationResult" do
    describe "#valid?" do
      it "returns true when valid is true" do
        result = described_class::ValidationResult.new(valid: true)
        expect(result.valid?).to be true
      end

      it "returns false when valid is false" do
        result = described_class::ValidationResult.new(valid: false)
        expect(result.valid?).to be false
      end
    end

    describe "#to_s" do
      it "returns success message for valid result" do
        result = described_class::ValidationResult.new(valid: true)
        expect(result.to_s).to eq("Valid bz2 file")
      end

      it "returns error message for invalid result" do
        result = described_class::ValidationResult.new(valid: false, message: "Test error")
        expect(result.to_s).to eq("Invalid: Test error")
      end
    end
  end

  describe "constants" do
    it "has correct BZ2 magic bytes" do
      expect(described_class::BZ2_MAGIC).to eq("BZ")
    end

    it "has correct BZ2 version" do
      expect(described_class::BZ2_VERSION).to eq("h")
    end

    it "has valid block size range" do
      expect(described_class::BZ2_BLOCK_SIZES).to eq(("1".."9").to_a)
    end
  end
end
