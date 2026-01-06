# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Wp2txt Utils" do
  include Wp2txt

  describe "process_nested_structure" do
    it "parse nested structure replacing str in the format specified" do
      str_before1 = "[[ab[[cde[[alfa]]]]fg]]"
      str_after1  = "<<ab<<cde<<alfa>>>>fg>>"
      scanner1 = StringScanner.new(str_before1)
      str_processed = process_nested_structure(scanner1, "[[", "]]") do |content|
        "<<" + content + ">>"
      end
      expect(str_processed).to eq str_after1

      str_before = "#* {{quote-book|1503|year_published=1836|chapter=19 Henry VII. c. 5: Coin||A Collection of Statutes Connected with the General Administration of the Law|page=158|url=http://books.google.com/books?id=QtYuAAAAIAAJ
      |passage={{...}} every of them, being gold, whole and weight, shall '''go''' and be current in payment throughout this his realm for the sum that they were coined for.}}"
      str_after = "#* <<quote-book|1503|year_published=1836|chapter=19 Henry VII. c. 5: Coin||A Collection of Statutes Connected with the General Administration of the Law|page=158|url=http://books.google.com/books?id=QtYuAAAAIAAJ
      |passage=<<...>> every of them, being gold, whole and weight, shall '''go''' and be current in payment throughout this his realm for the sum that they were coined for.>>"
      scanner = StringScanner.new(str_before)
      str_processed = process_nested_structure(scanner, "{{", "}}") do |content|
        "<<" + content + ">>"
      end
      expect(str_processed).to eq str_after
    end
  end

  describe "special_chr" do
    it "replaces character references with real characters" do
      str_before = "&nbsp; &lt; &gt; &amp; &quot;"
      str_after  = "  < > & \""
      expect(special_chr(str_before)).to eq str_after
    end
  end

  describe "chrref_to_utf" do
    it "replaces character references with real characters" do
      str_before = "&#x266A;"
      str_after  = "♪"
      expect(chrref_to_utf(str_before)).to eq str_after
    end
  end

  describe "mndash" do
    it "replaces {mdash}, {ndash}, or {–} with '–'" do
      str_before = "{mdash} {ndash} {–}"
      str_after  = "– – –"
      expect(mndash(str_before)).to eq str_after
    end
  end

  describe "make_reference" do
    it "replaces <ref> tag with [ref]" do
      str_before = "<ref> ... </ref>"
      str_after  = "[ref] ... [/ref]"
      expect(make_reference(str_before)).to eq str_after
    end
  end

  describe "remove_table" do
    it "removes table formated parts" do
      str_before = "{| ... \n{| ... \n ...|}\n ...|}"
      str_after  = ""
      expect(remove_table(str_before)).to eq str_after
    end
  end

  describe "remove_hr" do
    it "removes horizontal lines with 4+ hyphens" do
      # MediaWiki requires 4+ hyphens for horizontal rules
      # The hyphens are removed but newlines around them are preserved
      str_before = "text\n----\nmore"
      str_after  = "text\n\nmore"
      expect(remove_hr(str_before)).to eq str_after
    end

    it "does not remove lines with fewer than 4 hyphens" do
      # Lines with fewer than 4 hyphens should be preserved
      str_before = "text\n--\n---\nmore"
      str_after  = "text\n--\n---\nmore"
      expect(remove_hr(str_before)).to eq str_after
    end
  end

  describe "remove_inbetween" do
    it "removes tags and its contents" do
      str_before1 = "<tag>abc</tag>"
      str_after1  = "abc"
      expect(remove_tag(str_before1)).to eq str_after1

      str_before2 = "[tag]def[/tag]"
      str_after2  = "def"
      expect(remove_inbetween(str_before2, ["[", "]"])).to eq str_after2
    end
  end

  describe "remove_directive" do
    it "removes directive" do
      str_before = "__abc__\n __def__"
      str_after  = "\n "
      expect(remove_directive(str_before)).to eq str_after
    end
  end

  describe "remove_emphasis" do
    it "removes directive" do
      str_before = "''abc''\n'''def'''"
      str_after  = "abc\ndef"
      expect(remove_emphasis(str_before)).to eq str_after
    end
  end

  describe "escape_nowiki" do
    it "replaces <nowiki>...</nowiki> with <nowiki-object_id>" do
      str_before = "<nowiki>[[abc]]</nowiki>def<nowiki>[[ghi]]</nowiki>"
      str_after  = Regexp.new("<nowiki-\\d+>def<nowiki-\\d+>")
      expect(escape_nowiki(str_before)).to match str_after
    end
  end

  describe "unescape_nowiki" do
    it "replaces <nowiki-object_id> with string stored elsewhere" do
      @nowikis = { 123 => "[[abc]]", 124 => "[[ghi]]" }
      str_before = "<nowiki-123>def<nowiki-124>"
      str_after  = "[[abc]]def[[ghi]]"
      expect(unescape_nowiki(str_before)).to eq str_after
    end
  end

  describe "process_interwiki_links" do
    it "formats text link and remove brackets" do
      a1 = "[[a b]]"
      b1 = "[[a b|c]]"
      c1 = "[[a|b|c]]"
      d1 = "[[硬口蓋鼻音|[ɲ], /J/]]"
      a2 = process_interwiki_links(a1)
      b2 = process_interwiki_links(b1)
      c2 = process_interwiki_links(c1)
      d2 = process_interwiki_links(d1)
      expect(a2).to eq "a b"
      expect(b2).to eq "c"
      expect(c2).to eq "b|c"
      expect(d2).to eq "[ɲ], /J/"
    end
  end

  describe "process_external_links" do
    it "formats text link and remove brackets" do
      a1 = "[http://yohasebe.com yohasebe.com]"
      b1 = "[http://yohasebe.com]"
      c1 = "* Turkish: {{t+|tr|köken bilimi}}]], {{t+|tr|etimoloji}}"
      a2 = process_external_links(a1)
      b2 = process_external_links(b1)
      c2 = process_external_links(c1)
      expect(a2).to eq "yohasebe.com"
      expect(b2).to eq "http://yohasebe.com"
      expect(c2).to eq "* Turkish: {{t+|tr|köken bilimi}}]], {{t+|tr|etimoloji}}"
    end
  end

  describe "correct_inline_template" do
    it "removes brackets and leaving some text" do
      str_before1 = "{{MedalCountry | {{JPN}} }}"
      str_after1  = "JPN"
      expect(correct_inline_template(str_before1)).to eq str_after1

      str_before2 = "{{lang|en|Japan}}"
      str_after2  = "Japan"
      expect(correct_inline_template(str_before2)).to eq str_after2

      str_before3 = "{{a|b=c|d=f}}"
      str_after3  = "c"
      expect(correct_inline_template(str_before3)).to eq str_after3

      str_before4 = "{{a|b|{{c|d|e}}}}"
      str_after4  = "b"
      expect(correct_inline_template(str_before4)).to eq str_after4

      str_before5 = "{{要出典範囲|日本人に多く見受けられる|date=2013年8月|title=日本人特有なのか、本当に多いのかを示す必要がある}}"
      str_after5 = "日本人に多く見受けられる"
      expect(correct_inline_template(str_before5)).to eq str_after5
    end
  end
end
