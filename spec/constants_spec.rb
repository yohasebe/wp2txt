# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe "Wp2txt Constants" do
  describe "Time Constants" do
    it "defines SECONDS_PER_DAY" do
      expect(Wp2txt::SECONDS_PER_DAY).to eq(86_400)
    end

    it "defines SECONDS_PER_HOUR" do
      expect(Wp2txt::SECONDS_PER_HOUR).to eq(3_600)
    end

    it "defines SECONDS_PER_MINUTE" do
      expect(Wp2txt::SECONDS_PER_MINUTE).to eq(60)
    end
  end

  describe "Cache Settings" do
    it "defines DEFAULT_DUMP_EXPIRY_DAYS" do
      expect(Wp2txt::DEFAULT_DUMP_EXPIRY_DAYS).to eq(30)
    end

    it "defines DEFAULT_CATEGORY_CACHE_EXPIRY_DAYS" do
      expect(Wp2txt::DEFAULT_CATEGORY_CACHE_EXPIRY_DAYS).to eq(7)
    end

  end

  describe "Network Settings" do
    it "defines DEFAULT_HTTP_TIMEOUT" do
      expect(Wp2txt::DEFAULT_HTTP_TIMEOUT).to eq(30)
    end

    it "defines DEFAULT_PROGRESS_INTERVAL" do
      expect(Wp2txt::DEFAULT_PROGRESS_INTERVAL).to eq(10)
    end

    it "defines INDEX_PROGRESS_THRESHOLD" do
      expect(Wp2txt::INDEX_PROGRESS_THRESHOLD).to eq(500_000)
    end

    it "defines DEFAULT_TOP_N_SECTIONS" do
      expect(Wp2txt::DEFAULT_TOP_N_SECTIONS).to eq(50)
    end

    it "defines RESUME_METADATA_MAX_AGE_DAYS" do
      expect(Wp2txt::RESUME_METADATA_MAX_AGE_DAYS).to eq(7)
    end

    it "defines MAX_HTTP_RETRIES" do
      expect(Wp2txt::MAX_HTTP_RETRIES).to eq(3)
    end
  end

  describe "Processing Limits" do
    it "defines MAX_NESTING_ITERATIONS" do
      expect(Wp2txt::MAX_NESTING_ITERATIONS).to eq(50_000)
    end

    it "defines DEFAULT_BUFFER_SIZE" do
      expect(Wp2txt::DEFAULT_BUFFER_SIZE).to eq(10_485_760) # 10 MB
    end
  end

  describe "File Size Units" do
    it "defines BYTES_PER_KB" do
      expect(Wp2txt::BYTES_PER_KB).to eq(1024)
    end

    it "defines BYTES_PER_MB" do
      expect(Wp2txt::BYTES_PER_MB).to eq(1024 * 1024)
    end

    it "defines BYTES_PER_GB" do
      expect(Wp2txt::BYTES_PER_GB).to eq(1024 * 1024 * 1024)
    end
  end

  describe ".days_to_seconds" do
    it "converts days to seconds" do
      expect(Wp2txt.days_to_seconds(1)).to eq(86_400)
      expect(Wp2txt.days_to_seconds(7)).to eq(7 * 86_400)
      expect(Wp2txt.days_to_seconds(0.5)).to eq(43_200)
    end
  end

  describe ".file_fresh?" do
    let(:temp_file) { Tempfile.new("test_file") }

    after { temp_file.unlink }

    it "returns true for recently created file" do
      expect(Wp2txt.file_fresh?(temp_file.path, 1)).to be true
    end

    it "returns false for non-existent file" do
      expect(Wp2txt.file_fresh?("/nonexistent/path", 1)).to be false
    end
  end

  describe ".file_age_days" do
    let(:temp_file) { Tempfile.new("test_file") }

    after { temp_file.unlink }

    it "returns age in days for existing file" do
      age = Wp2txt.file_age_days(temp_file.path)
      expect(age).to be_a(Float)
      expect(age).to be >= 0
      expect(age).to be < 1 # File just created
    end

    it "returns nil for non-existent file" do
      expect(Wp2txt.file_age_days("/nonexistent/path")).to be_nil
    end
  end

  describe ".format_file_size" do
    it "formats bytes" do
      expect(Wp2txt.format_file_size(500)).to eq("500 B")
    end

    it "formats kilobytes" do
      expect(Wp2txt.format_file_size(2048)).to eq("2.0 KB")
    end

    it "formats megabytes" do
      expect(Wp2txt.format_file_size(5_242_880)).to eq("5.0 MB")
    end

    it "formats gigabytes" do
      expect(Wp2txt.format_file_size(2_147_483_648)).to eq("2.0 GB")
    end
  end
end
