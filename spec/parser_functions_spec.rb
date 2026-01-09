# frozen_string_literal: true

require "spec_helper"

RSpec.describe Wp2txt::ParserFunctions do
  let(:parser) { described_class.new }

  describe "#if" do
    it "returns then-value when condition is non-empty" do
      expect(parser.evaluate("{{#if:yes|true|false}}")).to eq("true")
    end

    it "returns else-value when condition is empty" do
      expect(parser.evaluate("{{#if:|true|false}}")).to eq("false")
    end

    it "returns else-value when condition is whitespace only" do
      expect(parser.evaluate("{{#if:   |true|false}}")).to eq("false")
    end

    it "returns then-value with text condition" do
      expect(parser.evaluate("{{#if:something|yes|no}}")).to eq("yes")
    end

    it "returns empty when no else-value and condition is empty" do
      expect(parser.evaluate("{{#if:|true}}")).to eq("")
    end

    it "handles nested #if" do
      expect(parser.evaluate("{{#if:x|{{#if:y|inner|}}|outer}}")).to eq("inner")
    end
  end

  describe "#ifeq" do
    it "returns then-value when strings are equal" do
      expect(parser.evaluate("{{#ifeq:foo|foo|equal|not equal}}")).to eq("equal")
    end

    it "returns else-value when strings differ" do
      expect(parser.evaluate("{{#ifeq:foo|bar|equal|not equal}}")).to eq("not equal")
    end

    it "handles numeric comparison" do
      expect(parser.evaluate("{{#ifeq:01|1|equal|not equal}}")).to eq("equal")
    end

    it "handles case-sensitive comparison" do
      expect(parser.evaluate("{{#ifeq:Foo|foo|equal|not equal}}")).to eq("not equal")
    end

    it "trims whitespace in comparison" do
      expect(parser.evaluate("{{#ifeq: foo |foo|equal|not equal}}")).to eq("equal")
    end

    it "returns empty when no else-value and not equal" do
      expect(parser.evaluate("{{#ifeq:a|b|equal}}")).to eq("")
    end
  end

  describe "#switch" do
    it "returns matching case value" do
      expect(parser.evaluate("{{#switch:b|a=first|b=second|c=third}}")).to eq("second")
    end

    it "returns default value when no match" do
      expect(parser.evaluate("{{#switch:x|a=first|b=second|#default=none}}")).to eq("none")
    end

    it "returns last unnamed value as default" do
      expect(parser.evaluate("{{#switch:x|a=first|b=second|fallback}}")).to eq("fallback")
    end

    it "returns empty when no match and no default" do
      expect(parser.evaluate("{{#switch:x|a=first|b=second}}")).to eq("")
    end

    it "handles fall-through cases" do
      expect(parser.evaluate("{{#switch:b|a|b|c=result}}")).to eq("result")
    end

    it "handles numeric matching" do
      expect(parser.evaluate("{{#switch:2|1=one|2=two|3=three}}")).to eq("two")
    end

    it "trims whitespace in comparisons" do
      expect(parser.evaluate("{{#switch: b |a=first| b =second}}")).to eq("second")
    end
  end

  describe "#ifexpr" do
    it "returns then-value when expression is non-zero" do
      expect(parser.evaluate("{{#ifexpr:1|yes|no}}")).to eq("yes")
    end

    it "returns else-value when expression is zero" do
      expect(parser.evaluate("{{#ifexpr:0|yes|no}}")).to eq("no")
    end

    it "evaluates simple arithmetic" do
      expect(parser.evaluate("{{#ifexpr:2+2=4|yes|no}}")).to eq("yes")
    end

    it "evaluates comparison operators" do
      expect(parser.evaluate("{{#ifexpr:5>3|yes|no}}")).to eq("yes")
    end

    it "handles negative results" do
      expect(parser.evaluate("{{#ifexpr:3-5|yes|no}}")).to eq("yes")
    end
  end

  describe "#expr" do
    it "evaluates addition" do
      expect(parser.evaluate("{{#expr:2+3}}")).to eq("5")
    end

    it "evaluates subtraction" do
      expect(parser.evaluate("{{#expr:10-3}}")).to eq("7")
    end

    it "evaluates multiplication" do
      expect(parser.evaluate("{{#expr:4*5}}")).to eq("20")
    end

    it "evaluates division" do
      expect(parser.evaluate("{{#expr:20/4}}")).to eq("5")
    end

    it "evaluates modulo" do
      expect(parser.evaluate("{{#expr:17 mod 5}}")).to eq("2")
    end

    it "evaluates parentheses" do
      expect(parser.evaluate("{{#expr:(2+3)*4}}")).to eq("20")
    end

    it "evaluates power" do
      expect(parser.evaluate("{{#expr:2^3}}")).to eq("8")
    end

    it "handles decimal results" do
      result = parser.evaluate("{{#expr:10/3}}")
      expect(result.to_f).to be_within(0.01).of(3.33)
    end

    it "handles comparison operators returning 1 or 0" do
      expect(parser.evaluate("{{#expr:5>3}}")).to eq("1")
      expect(parser.evaluate("{{#expr:5<3}}")).to eq("0")
    end

    it "handles equality comparison" do
      expect(parser.evaluate("{{#expr:5=5}}")).to eq("1")
      expect(parser.evaluate("{{#expr:5=6}}")).to eq("0")
    end

    it "handles and/or operators" do
      expect(parser.evaluate("{{#expr:1 and 1}}")).to eq("1")
      expect(parser.evaluate("{{#expr:1 and 0}}")).to eq("0")
      expect(parser.evaluate("{{#expr:0 or 1}}")).to eq("1")
    end

    it "handles unary minus" do
      expect(parser.evaluate("{{#expr:-5}}")).to eq("-5")
    end

    it "returns error indicator for invalid expressions" do
      expect(parser.evaluate("{{#expr:invalid}}")).to eq("")
    end
  end

  describe "#len" do
    it "returns string length" do
      expect(parser.evaluate("{{#len:hello}}")).to eq("5")
    end

    it "counts unicode characters" do
      expect(parser.evaluate("{{#len:日本語}}")).to eq("3")
    end

    it "returns 0 for empty string" do
      expect(parser.evaluate("{{#len:}}")).to eq("0")
    end
  end

  describe "#pos" do
    it "returns position of substring" do
      expect(parser.evaluate("{{#pos:hello|l}}")).to eq("2")
    end

    it "returns empty when not found" do
      expect(parser.evaluate("{{#pos:hello|x}}")).to eq("")
    end

    it "returns position of first occurrence" do
      expect(parser.evaluate("{{#pos:hello|l}}")).to eq("2")
    end
  end

  describe "#sub" do
    it "extracts substring from start" do
      expect(parser.evaluate("{{#sub:hello|0|3}}")).to eq("hel")
    end

    it "extracts substring from position" do
      expect(parser.evaluate("{{#sub:hello|2|3}}")).to eq("llo")
    end

    it "handles negative start (from end)" do
      expect(parser.evaluate("{{#sub:hello|-2}}")).to eq("lo")
    end

    it "handles length beyond string" do
      expect(parser.evaluate("{{#sub:hello|0|100}}")).to eq("hello")
    end
  end

  describe "#replace" do
    it "replaces substring" do
      expect(parser.evaluate("{{#replace:hello world|world|universe}}")).to eq("hello universe")
    end

    it "replaces all occurrences" do
      expect(parser.evaluate("{{#replace:ababa|a|x}}")).to eq("xbxbx")
    end

    it "handles empty replacement" do
      expect(parser.evaluate("{{#replace:hello|l|}}")).to eq("heo")
    end
  end

  describe "#titleparts" do
    it "extracts first part of title" do
      expect(parser.evaluate("{{#titleparts:Talk:Foo/Bar/Baz|1}}")).to eq("Talk:Foo")
    end

    it "extracts multiple parts" do
      expect(parser.evaluate("{{#titleparts:Talk:Foo/Bar/Baz|2}}")).to eq("Talk:Foo/Bar")
    end

    it "extracts from offset" do
      expect(parser.evaluate("{{#titleparts:Talk:Foo/Bar/Baz|1|1}}")).to eq("Bar")
    end

    it "handles negative count (from end)" do
      expect(parser.evaluate("{{#titleparts:Talk:Foo/Bar/Baz|-1}}")).to eq("Talk:Foo/Bar")
    end
  end

  describe "#time" do
    let(:parser_with_date) { described_class.new(reference_date: Time.new(2024, 6, 15, 10, 30, 45)) }

    it "formats year" do
      expect(parser_with_date.evaluate("{{#time:Y}}")).to eq("2024")
    end

    it "formats month name" do
      expect(parser_with_date.evaluate("{{#time:F}}")).to eq("June")
    end

    it "formats day" do
      expect(parser_with_date.evaluate("{{#time:j}}")).to eq("15")
    end

    it "formats full date" do
      expect(parser_with_date.evaluate("{{#time:Y-m-d}}")).to eq("2024-06-15")
    end

    it "parses input date" do
      expect(parser.evaluate("{{#time:Y|2020-05-15}}")).to eq("2020")
    end
  end

  describe "integration with template_expander" do
    include Wp2txt

    it "expands parser functions in format_wiki" do
      input = "Result: {{#if:yes|shown|hidden}}"
      result = format_wiki(input, title: "Test", expand_templates: true)
      expect(result).to include("Result: shown")
    end

    it "handles parser functions within templates" do
      input = "{{#switch:2|1=one|2=two|3=three}}"
      result = format_wiki(input, title: "Test", expand_templates: true)
      expect(result).to eq("two")
    end

    it "handles nested parser functions and templates" do
      input = "{{#if:yes|{{circa|1500}}|unknown}}"
      result = format_wiki(input, title: "Test", expand_templates: true)
      expect(result).to eq("c. 1500")
    end
  end

  describe "edge cases" do
    it "handles malformed parser function gracefully" do
      expect(parser.evaluate("{{#if:}}")).to eq("")
    end

    it "handles unknown parser function" do
      expect(parser.evaluate("{{#unknown:foo|bar}}")).to eq("")
    end

    it "handles deeply nested functions" do
      result = parser.evaluate("{{#if:x|{{#ifeq:a|a|{{#switch:1|1=deep}}|}}|}}")
      expect(result).to eq("deep")
    end

    it "preserves text around parser functions" do
      expect(parser.evaluate("Before {{#if:x|middle|}} after")).to eq("Before middle after")
    end
  end
end
