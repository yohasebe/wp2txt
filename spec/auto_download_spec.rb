# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require_relative "../lib/wp2txt/multistream"
require_relative "../lib/wp2txt/cli"

RSpec.describe "Wp2txt Auto Download" do
  include Wp2txt

  describe "DumpManager" do
    let(:cache_dir) { File.join(Dir.tmpdir, "wp2txt_test_cache_#{Process.pid}") }

    after do
      FileUtils.rm_rf(cache_dir) if File.exist?(cache_dir)
    end

    describe ".default_cache_dir" do
      it "returns ~/.wp2txt/cache by default" do
        expect(Wp2txt::DumpManager.default_cache_dir).to eq(File.expand_path("~/.wp2txt/cache"))
      end
    end

    describe "#initialize" do
      it "accepts custom cache directory" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir)
        expect(manager.cache_dir).to eq(cache_dir)
      end

      it "uses default cache directory when not specified" do
        manager = Wp2txt::DumpManager.new(:ja)
        expect(manager.cache_dir).to eq(Wp2txt::DumpManager.default_cache_dir)
      end
    end

    describe "#cache_status" do
      it "returns status hash with expected keys" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir)
        # Stub the dump date to avoid network call
        allow(manager).to receive(:latest_dump_date).and_return("20260101")

        status = manager.cache_status
        expect(status).to have_key(:lang)
        expect(status).to have_key(:cache_dir)
        expect(status).to have_key(:index_exists)
        expect(status).to have_key(:multistream_exists)
        expect(status).to have_key(:age_days)
        expect(status).to have_key(:mtime)
        expect(status).to have_key(:expiry_days)
        expect(status[:lang]).to eq(:ja)
      end

      it "returns false for index_exists when cache is empty" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir)
        allow(manager).to receive(:latest_dump_date).and_return("20260101")

        status = manager.cache_status
        expect(status[:index_exists]).to be false
        expect(status[:multistream_exists]).to be false
      end
    end

    describe "#cache_age_days" do
      it "returns nil when cache does not exist" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir)
        allow(manager).to receive(:latest_dump_date).and_return("20260101")

        expect(manager.cache_age_days).to be_nil
      end

      it "returns age in days when cache exists" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir)
        allow(manager).to receive(:latest_dump_date).and_return("20260101")

        # Create a fake index file
        index_path = manager.cached_index_path
        FileUtils.mkdir_p(File.dirname(index_path))
        File.write(index_path, "test")

        age = manager.cache_age_days
        expect(age).to be_a(Float)
        expect(age).to be >= 0
        expect(age).to be < 1  # Just created
      end
    end

    describe "#cache_mtime" do
      it "returns nil when cache does not exist" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir)
        allow(manager).to receive(:latest_dump_date).and_return("20260101")

        expect(manager.cache_mtime).to be_nil
      end

      it "returns modification time when cache exists" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir)
        allow(manager).to receive(:latest_dump_date).and_return("20260101")

        # Create a fake index file
        index_path = manager.cached_index_path
        FileUtils.mkdir_p(File.dirname(index_path))
        File.write(index_path, "test")

        mtime = manager.cache_mtime
        expect(mtime).to be_a(Time)
      end
    end

    describe "#cache_stale?" do
      it "returns true when cache does not exist" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir)
        allow(manager).to receive(:latest_dump_date).and_return("20260101")

        expect(manager.cache_stale?).to be true
      end

      it "returns false when cache is fresh" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir, dump_expiry_days: 30)
        allow(manager).to receive(:latest_dump_date).and_return("20260101")

        # Create a fake index file (just created = fresh)
        index_path = manager.cached_index_path
        FileUtils.mkdir_p(File.dirname(index_path))
        File.write(index_path, "test")

        expect(manager.cache_stale?).to be false
      end

      it "returns true when cache is older than expiry days" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir, dump_expiry_days: 1)
        allow(manager).to receive(:latest_dump_date).and_return("20260101")

        # Create a fake index file
        index_path = manager.cached_index_path
        FileUtils.mkdir_p(File.dirname(index_path))
        File.write(index_path, "test")

        # Set modification time to 2 days ago
        old_time = Time.now - (2 * 86400)
        File.utime(old_time, old_time, index_path)

        expect(manager.cache_stale?).to be true
      end
    end

    describe "#clear_cache!" do
      it "removes language-specific cache directory" do
        manager = Wp2txt::DumpManager.new(:ja, cache_dir: cache_dir)
        lang_dir = File.join(cache_dir, "jawiki")
        FileUtils.mkdir_p(lang_dir)
        File.write(File.join(lang_dir, "test.txt"), "test")

        expect(File.exist?(lang_dir)).to be true
        manager.clear_cache!
        expect(File.exist?(lang_dir)).to be false
      end
    end

    describe ".clear_all_cache!" do
      it "removes entire cache directory" do
        FileUtils.mkdir_p(File.join(cache_dir, "jawiki"))
        FileUtils.mkdir_p(File.join(cache_dir, "enwiki"))
        File.write(File.join(cache_dir, "jawiki", "test.txt"), "test")

        Wp2txt::DumpManager.clear_all_cache!(cache_dir)
        expect(File.exist?(cache_dir)).to be false
      end
    end
  end

  describe "Wp2txt::CLI" do
    describe ".valid_language_code?" do
      it "accepts valid 2-letter codes" do
        expect(Wp2txt::CLI.valid_language_code?("ja")).to be true
        expect(Wp2txt::CLI.valid_language_code?("en")).to be true
        expect(Wp2txt::CLI.valid_language_code?("zh")).to be true
        expect(Wp2txt::CLI.valid_language_code?("de")).to be true
      end

      it "accepts valid longer codes" do
        expect(Wp2txt::CLI.valid_language_code?("simple")).to be true
      end

      it "accepts hyphenated codes" do
        expect(Wp2txt::CLI.valid_language_code?("zh-yue")).to be true
      end

      it "rejects invalid codes" do
        expect(Wp2txt::CLI.valid_language_code?("INVALID")).to be false
        expect(Wp2txt::CLI.valid_language_code?("123")).to be false
        expect(Wp2txt::CLI.valid_language_code?("")).to be false
        expect(Wp2txt::CLI.valid_language_code?(nil)).to be false
      end
    end

    describe ".default_cache_dir" do
      it "returns ~/.wp2txt/cache" do
        expect(Wp2txt::CLI.default_cache_dir).to eq(File.expand_path("~/.wp2txt/cache"))
      end
    end

    describe ".parse_options" do
      let(:cache_dir) { File.join(Dir.tmpdir, "wp2txt_cli_test_#{Process.pid}") }

      before do
        FileUtils.mkdir_p(cache_dir)
      end

      after do
        FileUtils.rm_rf(cache_dir) if File.exist?(cache_dir)
      end

      it "accepts --lang option" do
        opts = Wp2txt::CLI.parse_options(["--lang=ja", "--cache-dir=#{cache_dir}"])
        expect(opts[:lang]).to eq("ja")
      end

      it "accepts --cache-dir option" do
        opts = Wp2txt::CLI.parse_options(["--lang=ja", "--cache-dir=#{cache_dir}"])
        expect(opts[:cache_dir]).to eq(cache_dir)
      end

      it "accepts --cache-status option" do
        opts = Wp2txt::CLI.parse_options(["--cache-status", "--cache-dir=#{cache_dir}"])
        expect(opts[:cache_status]).to be true
      end

      it "accepts --cache-clear option" do
        opts = Wp2txt::CLI.parse_options(["--cache-clear", "--cache-dir=#{cache_dir}"])
        expect(opts[:cache_clear]).to be true
      end

      it "allows --cache-status without --input or --lang" do
        opts = Wp2txt::CLI.parse_options(["--cache-status", "--cache-dir=#{cache_dir}"])
        expect(opts[:cache_status]).to be true
        expect(opts[:input]).to be_nil
        expect(opts[:lang]).to be_nil
      end

      it "allows --cache-clear without --input or --lang" do
        opts = Wp2txt::CLI.parse_options(["--cache-clear", "--cache-dir=#{cache_dir}"])
        expect(opts[:cache_clear]).to be true
      end

      context "input source validation" do
        it "requires either --input or --lang for normal operation" do
          suppress_stderr do
            expect { Wp2txt::CLI.parse_options(["--output-dir=#{cache_dir}"]) }.to raise_error(SystemExit)
          end
        end

        it "rejects both --input and --lang together" do
          # Create a dummy input file
          input_file = File.join(cache_dir, "test.xml")
          File.write(input_file, "<test/>")

          suppress_stderr do
            expect { Wp2txt::CLI.parse_options(["--input=#{input_file}", "--lang=ja"]) }.to raise_error(SystemExit)
          end
        end
      end

      context "--articles option" do
        it "accepts --articles with --lang" do
          opts = Wp2txt::CLI.parse_options(["--lang=ja", "--articles=認知言語学"])
          expect(opts[:articles]).to eq("認知言語学")
        end

        it "accepts multiple articles separated by comma" do
          opts = Wp2txt::CLI.parse_options(["--lang=ja", "--articles=認知言語学,生成文法,言語学"])
          expect(opts[:articles]).to eq("認知言語学,生成文法,言語学")
        end

        it "requires --lang when --articles is specified" do
          suppress_stderr do
            expect { Wp2txt::CLI.parse_options(["--articles=Test"]) }.to raise_error(SystemExit)
          end
        end

        it "rejects --articles with --input" do
          input_file = File.join(cache_dir, "test.xml")
          File.write(input_file, "<test/>")
          suppress_stderr do
            expect { Wp2txt::CLI.parse_options(["--input=#{input_file}", "--articles=Test"]) }.to raise_error(SystemExit)
          end
        end
      end
    end
  end

  describe "Article extraction" do
    describe "Wp2txt::CLI.parse_article_list" do
      it "parses single article" do
        articles = Wp2txt::CLI.parse_article_list("認知言語学")
        expect(articles).to eq(["認知言語学"])
      end

      it "parses multiple articles" do
        articles = Wp2txt::CLI.parse_article_list("認知言語学,生成文法,言語学")
        expect(articles).to eq(["認知言語学", "生成文法", "言語学"])
      end

      it "trims whitespace" do
        articles = Wp2txt::CLI.parse_article_list(" 認知言語学 , 生成文法 ")
        expect(articles).to eq(["認知言語学", "生成文法"])
      end

      it "returns empty array for nil" do
        articles = Wp2txt::CLI.parse_article_list(nil)
        expect(articles).to eq([])
      end
    end
  end
end
