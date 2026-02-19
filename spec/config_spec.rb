# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/wp2txt/config"
require "tmpdir"
require "fileutils"

RSpec.describe Wp2txt::Config do
  let(:tmpdir) { Dir.mktmpdir("wp2txt_config_test_") }
  let(:config_path) { File.join(tmpdir, "config.yml") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe ".default_path" do
    it "returns path in home directory" do
      expect(described_class.default_path).to include(".wp2txt")
      expect(described_class.default_path).to end_with("config.yml")
    end
  end

  describe ".load" do
    context "when config file does not exist" do
      it "returns default configuration" do
        config = described_class.load(config_path)

        expect(config.dump_expiry_days).to eq 30
        expect(config.category_expiry_days).to eq 7
        expect(config.cache_directory).to eq Wp2txt::Config::DEFAULT_CACHE_DIR
        expect(config.default_format).to eq "text"
        expect(config.default_depth).to eq 0
      end
    end

    context "when config file exists" do
      it "loads settings from file" do
        File.write(config_path, <<~YAML)
          cache:
            dump_expiry_days: 60
            category_expiry_days: 14
            directory: /custom/cache
          defaults:
            format: json
            depth: 2
        YAML

        config = described_class.load(config_path)

        expect(config.dump_expiry_days).to eq 60
        expect(config.category_expiry_days).to eq 14
        expect(config.cache_directory).to eq "/custom/cache"
        expect(config.default_format).to eq "json"
        expect(config.default_depth).to eq 2
      end

      it "uses defaults for missing keys" do
        File.write(config_path, <<~YAML)
          cache:
            dump_expiry_days: 45
        YAML

        config = described_class.load(config_path)

        expect(config.dump_expiry_days).to eq 45
        expect(config.category_expiry_days).to eq 7  # default
        expect(config.default_format).to eq "text"   # default
      end

      it "handles empty file" do
        File.write(config_path, "")

        config = described_class.load(config_path)

        expect(config.dump_expiry_days).to eq 30
      end

      it "handles malformed YAML gracefully" do
        File.write(config_path, "invalid: yaml: content: [")

        config = described_class.load(config_path)

        # Should return defaults on parse error
        expect(config.dump_expiry_days).to eq 30
      end
    end
  end

  describe "#save" do
    it "writes configuration to file" do
      config = described_class.new(
        dump_expiry_days: 45,
        category_expiry_days: 10,
        cache_directory: "/my/cache",
        default_format: "json",
        default_depth: 1
      )

      config.save(config_path)

      expect(File.exist?(config_path)).to be true
      loaded = described_class.load(config_path)
      expect(loaded.dump_expiry_days).to eq 45
      expect(loaded.category_expiry_days).to eq 10
      expect(loaded.cache_directory).to eq "/my/cache"
      expect(loaded.default_format).to eq "json"
      expect(loaded.default_depth).to eq 1
    end

    it "creates parent directories if needed" do
      nested_path = File.join(tmpdir, "nested", "dir", "config.yml")
      config = described_class.new

      config.save(nested_path)

      expect(File.exist?(nested_path)).to be true
    end
  end

  describe ".create_default" do
    it "creates a config file with default values" do
      described_class.create_default(config_path)

      expect(File.exist?(config_path)).to be true
      content = File.read(config_path)
      expect(content).to include("dump_expiry_days: 30")
      expect(content).to include("category_expiry_days: 7")
    end

    it "does not overwrite existing file" do
      File.write(config_path, "custom: value")

      result = described_class.create_default(config_path)

      expect(result).to be false
      expect(File.read(config_path)).to eq "custom: value"
    end

    it "can force overwrite with force option" do
      File.write(config_path, "custom: value")

      result = described_class.create_default(config_path, force: true)

      expect(result).to be true
      expect(File.read(config_path)).to include("dump_expiry_days: 30")
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      config = described_class.new(dump_expiry_days: 45)

      hash = config.to_h

      expect(hash).to be_a(Hash)
      expect(hash[:cache][:dump_expiry_days]).to eq 45
      expect(hash[:defaults][:format]).to eq "text"
    end
  end

  describe "validation" do
    it "clamps dump_expiry_days to valid range" do
      config = described_class.new(dump_expiry_days: -5)
      expect(config.dump_expiry_days).to eq 1

      config = described_class.new(dump_expiry_days: 400)
      expect(config.dump_expiry_days).to eq 365
    end

    it "clamps category_expiry_days to valid range" do
      config = described_class.new(category_expiry_days: 0)
      expect(config.category_expiry_days).to eq 1

      config = described_class.new(category_expiry_days: 100)
      expect(config.category_expiry_days).to eq 90
    end

    it "clamps default_depth to valid range" do
      config = described_class.new(default_depth: -1)
      expect(config.default_depth).to eq 0

      config = described_class.new(default_depth: 20)
      expect(config.default_depth).to eq 10
    end

    it "validates default_format" do
      config = described_class.new(default_format: "invalid")
      expect(config.default_format).to eq "text"

      config = described_class.new(default_format: "json")
      expect(config.default_format).to eq "json"
    end
  end
end
