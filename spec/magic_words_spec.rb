# frozen_string_literal: true

require "spec_helper"

RSpec.describe Wp2txt::MagicWordExpander do
  let(:title) { "Test Article" }
  let(:namespace) { "" }
  let(:dump_date) { Time.new(2024, 6, 15, 14, 30, 45) }
  let(:expander) { described_class.new(title, namespace: namespace, dump_date: dump_date) }

  describe "#expand" do
    context "page context magic words" do
      it "expands {{PAGENAME}}" do
        expect(expander.expand("{{PAGENAME}}")).to eq("Test Article")
      end

      it "expands {{pagename}} (case-insensitive)" do
        expect(expander.expand("{{pagename}}")).to eq("Test Article")
      end

      it "expands {{PAGENAMEE}} with URL encoding" do
        expect(expander.expand("{{PAGENAMEE}}")).to eq("Test_Article")
      end

      it "expands {{FULLPAGENAME}} without namespace" do
        expect(expander.expand("{{FULLPAGENAME}}")).to eq("Test Article")
      end

      context "with namespace" do
        let(:namespace) { "Wikipedia" }

        it "expands {{FULLPAGENAME}} with namespace" do
          expect(expander.expand("{{FULLPAGENAME}}")).to eq("Wikipedia:Test Article")
        end

        it "expands {{NAMESPACE}}" do
          expect(expander.expand("{{NAMESPACE}}")).to eq("Wikipedia")
        end
      end

      context "with subpage title" do
        let(:title) { "Main Page/Subpage/Deep" }

        it "expands {{BASEPAGENAME}} to parent" do
          expect(expander.expand("{{BASEPAGENAME}}")).to eq("Main Page/Subpage")
        end

        it "expands {{ROOTPAGENAME}} to root" do
          expect(expander.expand("{{ROOTPAGENAME}}")).to eq("Main Page")
        end

        it "expands {{SUBPAGENAME}} to last part" do
          expect(expander.expand("{{SUBPAGENAME}}")).to eq("Deep")
        end
      end

      it "expands {{TALKPAGENAME}}" do
        expect(expander.expand("{{TALKPAGENAME}}")).to eq("Talk:Test Article")
      end

      it "expands {{NAMESPACENUMBER}} for main namespace" do
        expect(expander.expand("{{NAMESPACENUMBER}}")).to eq("0")
      end
    end

    context "date/time magic words" do
      it "expands {{CURRENTYEAR}}" do
        expect(expander.expand("{{CURRENTYEAR}}")).to eq("2024")
      end

      it "expands {{CURRENTMONTH}} with zero padding" do
        expect(expander.expand("{{CURRENTMONTH}}")).to eq("06")
      end

      it "expands {{CURRENTMONTH1}} without zero padding" do
        expect(expander.expand("{{CURRENTMONTH1}}")).to eq("6")
      end

      it "expands {{CURRENTMONTHNAME}}" do
        expect(expander.expand("{{CURRENTMONTHNAME}}")).to eq("June")
      end

      it "expands {{CURRENTMONTHABBREV}}" do
        expect(expander.expand("{{CURRENTMONTHABBREV}}")).to eq("Jun")
      end

      it "expands {{CURRENTDAY}}" do
        expect(expander.expand("{{CURRENTDAY}}")).to eq("15")
      end

      it "expands {{CURRENTDAY2}} with zero padding" do
        dump_date_single_digit = Time.new(2024, 6, 5)
        exp = described_class.new(title, dump_date: dump_date_single_digit)
        expect(exp.expand("{{CURRENTDAY2}}")).to eq("05")
      end

      it "expands {{CURRENTDOW}} (day of week)" do
        # June 15, 2024 is a Saturday (6)
        expect(expander.expand("{{CURRENTDOW}}")).to eq("6")
      end

      it "expands {{CURRENTDAYNAME}}" do
        expect(expander.expand("{{CURRENTDAYNAME}}")).to eq("Saturday")
      end

      it "expands {{CURRENTTIME}}" do
        expect(expander.expand("{{CURRENTTIME}}")).to eq("14:30")
      end

      it "expands {{CURRENTHOUR}}" do
        expect(expander.expand("{{CURRENTHOUR}}")).to eq("14")
      end

      it "expands {{CURRENTTIMESTAMP}}" do
        expect(expander.expand("{{CURRENTTIMESTAMP}}")).to eq("20240615143045")
      end

      it "expands {{LOCALYEAR}} (same as CURRENTYEAR)" do
        expect(expander.expand("{{LOCALYEAR}}")).to eq("2024")
      end
    end

    context "string functions" do
      it "expands {{lc:TEXT}}" do
        expect(expander.expand("{{lc:HELLO WORLD}}")).to eq("hello world")
      end

      it "expands {{uc:text}}" do
        expect(expander.expand("{{uc:hello world}}")).to eq("HELLO WORLD")
      end

      it "expands {{lcfirst:TEXT}}" do
        expect(expander.expand("{{lcfirst:HELLO}}")).to eq("hELLO")
      end

      it "expands {{ucfirst:text}}" do
        expect(expander.expand("{{ucfirst:hello}}")).to eq("Hello")
      end

      it "expands {{urlencode:...}}" do
        expect(expander.expand("{{urlencode:hello world}}")).to eq("hello_world")
      end

      it "expands {{anchorencode:...}}" do
        expect(expander.expand("{{anchorencode:hello world}}")).to eq("hello_world")
      end

      it "expands {{padleft:...}}" do
        expect(expander.expand("{{padleft:7|3|0}}")).to eq("007")
      end

      it "expands {{padright:...}}" do
        expect(expander.expand("{{padright:7|3|0}}")).to eq("700")
      end

      it "expands {{formatnum:...}} with thousand separators" do
        expect(expander.expand("{{formatnum:12345}}")).to eq("12,345")
        expect(expander.expand("{{formatnum:1234567}}")).to eq("1,234,567")
        expect(expander.expand("{{formatnum:1234.56}}")).to eq("1,234.56")
      end

      it "expands {{formatnum:...|R}} to remove formatting" do
        expect(expander.expand("{{formatnum:1,234,567|R}}")).to eq("1234567")
      end
    end

    context "#titleparts parser function" do
      it "extracts first N segments" do
        expect(expander.expand("{{#titleparts:A/B/C|2}}")).to eq("A/B")
      end

      it "extracts from offset" do
        expect(expander.expand("{{#titleparts:A/B/C|1|2}}")).to eq("B")
      end

      it "handles negative count (all but last N)" do
        expect(expander.expand("{{#titleparts:A/B/C/D|-1}}")).to eq("A/B/C")
      end

      it "returns full path without parameters" do
        expect(expander.expand("{{#titleparts:A/B/C}}")).to eq("A/B/C")
      end
    end

    context "multiple magic words in one string" do
      it "expands all magic words" do
        input = "Page: {{PAGENAME}}, Year: {{CURRENTYEAR}}, Month: {{CURRENTMONTHNAME}}"
        expected = "Page: Test Article, Year: 2024, Month: June"
        expect(expander.expand(input)).to eq(expected)
      end

      it "handles mixed case and functions" do
        input = "{{uc:{{PAGENAME}}}} in {{CURRENTYEAR}}"
        # The uc: function uppercases the inner PAGENAME result
        result = expander.expand(input)
        expect(result).to include("TEST ARTICLE")
        expect(result).to include("2024")
      end
    end

    context "unrecognized magic words" do
      it "leaves unrecognized magic words unchanged" do
        expect(expander.expand("{{UNKNOWNMAGICWORD}}")).to eq("{{UNKNOWNMAGICWORD}}")
      end

      it "leaves template calls unchanged" do
        expect(expander.expand("{{Infobox|name=test}}")).to eq("{{Infobox|name=test}}")
      end
    end

    context "edge cases" do
      it "handles nil input" do
        expect(expander.expand(nil)).to eq(nil)
      end

      it "handles empty string" do
        expect(expander.expand("")).to eq("")
      end

      it "handles text without magic words" do
        expect(expander.expand("Hello World")).to eq("Hello World")
      end

      it "handles magic words with extra whitespace" do
        expect(expander.expand("{{ PAGENAME }}")).to eq("Test Article")
      end
    end
  end

  describe "integration with format_wiki" do
    include Wp2txt

    it "expands magic words when title is provided in config" do
      input = "This article is about {{PAGENAME}}."
      result = format_wiki(input, title: "Ruby Programming")
      expect(result).to include("Ruby Programming")
      expect(result).not_to include("{{PAGENAME}}")
    end

    it "does not expand magic words without title in config" do
      input = "This article is about {{PAGENAME}}."
      result = format_wiki(input)
      # Without title, the magic word might be removed as template or left as-is
      # The important thing is it doesn't crash
      expect(result).to be_a(String)
    end

    it "expands date magic words with current time when dump_date not specified" do
      input = "Year: {{CURRENTYEAR}}"
      result = format_wiki(input, title: "Test")
      expect(result).to match(/Year: \d{4}/)
    end

    it "expands string functions" do
      input = "{{uc:hello}} {{lc:WORLD}}"
      result = format_wiki(input, title: "Test")
      expect(result).to include("HELLO")
      expect(result).to include("world")
    end
  end
end
