# frozen_string_literal: true

require "spec_helper"
require "wp2txt/ractor_worker"

RSpec.describe Wp2txt::RactorWorker do
  describe "MINIMUM_RUBY_VERSION" do
    it "is set to 4.0" do
      expect(described_class::MINIMUM_RUBY_VERSION).to eq("4.0")
    end
  end

  describe "OPERATIONS" do
    it "includes expected operations" do
      expect(described_class::OPERATIONS).to include(:process_article)
      expect(described_class::OPERATIONS).to include(:double)
      expect(described_class::OPERATIONS).to include(:fib)
    end

    it "does not include removed operations" do
      expect(described_class::OPERATIONS).not_to include(:regex_transform)
      expect(described_class::OPERATIONS).not_to include(:format_wiki)
    end
  end

  describe ".ruby_version_sufficient?" do
    it "returns boolean based on Ruby version" do
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("4.0")
        expect(described_class.ruby_version_sufficient?).to be false
      else
        expect(described_class.ruby_version_sufficient?).to be true
      end
    end
  end

  describe ".available?" do
    it "returns a boolean" do
      result = described_class.available?
      expect([true, false]).to include(result)
    end

    it "caches the result" do
      result1 = described_class.available?
      result2 = described_class.available?
      expect(result1).to eq(result2)
    end

    it "returns false on Ruby < 4.0" do
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("4.0")
        if described_class.instance_variable_defined?(:@available)
          described_class.remove_instance_variable(:@available)
        end
        expect(described_class.available?).to be false
      end
    end
  end

  describe ".optimal_workers" do
    it "returns a positive integer" do
      result = described_class.optimal_workers
      expect(result).to be_a(Integer)
      expect(result).to be >= 1
    end

    it "does not exceed CPU count" do
      result = described_class.optimal_workers
      expect(result).to be <= Etc.nprocessors
    end
  end

  describe ".deep_freeze" do
    it "freezes a hash" do
      hash = { a: 1, b: "hello" }
      frozen = described_class.deep_freeze(hash)
      expect(frozen).to be_frozen
      expect(frozen[:b]).to be_frozen
    end

    it "freezes nested structures" do
      nested = { a: [1, 2, { b: "c" }] }
      frozen = described_class.deep_freeze(nested)
      expect(frozen).to be_frozen
      expect(frozen[:a]).to be_frozen
      expect(frozen[:a][2]).to be_frozen
    end

    it "handles already frozen objects" do
      str = "hello".freeze
      expect { described_class.deep_freeze(str) }.not_to raise_error
    end
  end

  describe ".process_single" do
    it "processes :double operation" do
      result = described_class.process_single(5, :double, {})
      expect(result).to eq(10)
    end

    it "processes :fib operation" do
      result = described_class.process_single(10, :fib, {})
      expect(result).to eq(55)
    end

    it "raises error for unknown operation" do
      expect {
        described_class.process_single(1, :unknown_op, {})
      }.to raise_error(/Unknown operation/)
    end
  end

  describe ".parallel_process" do
    context "with simple operations" do
      it "processes items with :double operation" do
        items = [1, 2, 3, 4, 5]
        results = described_class.parallel_process(
          items,
          operation: :double,
          config: {},
          num_workers: 2
        )
        expect(results).to eq([2, 4, 6, 8, 10])
      end

      it "returns empty array for empty input" do
        results = described_class.parallel_process(
          [],
          operation: :double,
          config: {}
        )
        expect(results).to eq([])
      end

      it "handles single item (falls back to sequential)" do
        results = described_class.parallel_process(
          [5],
          operation: :double,
          config: {}
        )
        expect(results).to eq([10])
      end

      it "preserves result order" do
        items = [5, 3, 7, 1, 9]
        results = described_class.parallel_process(
          items,
          operation: :double,
          config: {},
          num_workers: 4
        )
        expect(results).to eq([10, 6, 14, 2, 18])
      end
    end

    context "with process_article operation" do
      let(:config) { { format: :text, title: true, heading: true, category: true } }

      it "processes multiple articles" do
        items = [
          ["Article1", "Text one. [[Category:C1]]", false],
          ["Article2", "Text two. [[Category:C2]]", false]
        ]
        results = described_class.parallel_process(
          items,
          operation: :process_article,
          config: config,
          num_workers: 2
        )
        expect(results.size).to eq(2)
        expect(results.compact.size).to eq(2)
        expect(results[0]).to include("Article1")
        expect(results[1]).to include("Article2")
      end
    end
  end

  describe ".process_articles" do
    let(:config) { { format: :text, title: true, heading: true, category: true } }

    it "processes pages as [title, text] pairs" do
      pages = [
        ["Test1", "Content one. [[Category:Cat]]"],
        ["Test2", "Content two. [[Category:Cat]]"]
      ]
      results = described_class.process_articles(pages, config: config, num_workers: 2)
      expect(results.size).to eq(2)
      expect(results.compact.size).to eq(2)
    end

    it "includes article titles in output" do
      pages = [
        ["MyTitle", "Some content here."]
      ]
      results = described_class.process_articles(pages, config: config)
      expect(results.first).to include("MyTitle")
    end
  end
end
