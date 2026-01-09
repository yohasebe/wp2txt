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
    it "removes MediaWiki magic words" do
      # Use actual MediaWiki behavior switches (loaded from mediawiki_aliases.json)
      str_before = "__NOTOC__\n __TOC__"
      str_after  = "\n "
      expect(remove_directive(str_before)).to eq str_after
    end

    it "removes multilingual magic words" do
      # Japanese/German/other language magic words should also be removed
      str_before = "__KEIN_INHALTSVERZEICHNIS__\n__目次非表示__"
      str_after  = "\n"
      expect(remove_directive(str_before)).to eq str_after
    end

    it "preserves non-magic-word patterns" do
      # Arbitrary __something__ patterns that aren't valid magic words should be preserved
      # (This is the expected behavior with data-driven approach)
      str_before = "__custom_marker__"
      # With data-driven approach, unknown patterns are NOT removed
      expect(remove_directive(str_before)).to eq str_before
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

    it "handles pipe trick (empty display text)" do
      # Namespace prefix removal
      expect(process_interwiki_links("[[Wikipedia:著作権|]]")).to eq "著作権"
      expect(process_interwiki_links("[[Help:Contents|]]")).to eq "Contents"

      # Disambiguation suffix removal
      expect(process_interwiki_links("[[Tokyo (disambiguation)|]]")).to eq "Tokyo"
      expect(process_interwiki_links("[[Mercury (planet)|]]")).to eq "Mercury"

      # Comma suffix removal
      expect(process_interwiki_links("[[Paris, Texas|]]")).to eq "Paris"
      expect(process_interwiki_links("[[San Francisco, California|]]")).to eq "San Francisco"

      # Combined: namespace and disambiguation
      expect(process_interwiki_links("[[Wikipedia:Manual of Style (dates)|]]")).to eq "Manual of Style"
    end

    it "handles interwiki links" do
      expect(process_interwiki_links("[[Wikisource:日本国憲法]]")).to eq "Wikisource:日本国憲法"
      expect(process_interwiki_links("[[s:日本国憲法|日本国憲法]]")).to eq "日本国憲法"
    end
  end

  describe "apply_pipe_trick" do
    it "removes namespace prefix" do
      expect(apply_pipe_trick("Wikipedia:Manual of Style")).to eq "Manual of Style"
      expect(apply_pipe_trick("Help:Contents")).to eq "Contents"
      expect(apply_pipe_trick("カテゴリ:日本")).to eq "日本"
    end

    it "removes disambiguation parenthetical" do
      expect(apply_pipe_trick("Mercury (planet)")).to eq "Mercury"
      expect(apply_pipe_trick("東京 (曖昧さ回避)")).to eq "東京"
    end

    it "removes comma and following text" do
      expect(apply_pipe_trick("Paris, Texas")).to eq "Paris"
      expect(apply_pipe_trick("San Francisco, California")).to eq "San Francisco"
    end

    it "handles combined cases" do
      expect(apply_pipe_trick("Wikipedia:Manual of Style (dates)")).to eq "Manual of Style"
    end

    it "returns original if no transformation needed" do
      expect(apply_pipe_trick("Simple")).to eq "Simple"
      expect(apply_pipe_trick("東京")).to eq "東京"
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
      # Flag/country templates should be removed entirely
      str_before1 = "{{MedalCountry | {{JPN}} }}"
      str_after1  = ""
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

    it "removes citation templates entirely" do
      expect(correct_inline_template("{{cite web|url=http://example.com|title=Test}}")).to eq ""
      expect(correct_inline_template("{{cite book|title=Book|author=Author}}")).to eq ""
      expect(correct_inline_template("{{sfn|Smith|2020|p=123}}")).to eq ""
    end

    it "extracts content from language templates" do
      expect(correct_inline_template("{{lang-en|Hello}}")).to eq "Hello"
      expect(correct_inline_template("{{langwithname|en|English|Hello World}}")).to eq "Hello World"
      expect(correct_inline_template("{{IPA|/həˈloʊ/}}")).to eq "/həˈloʊ/"
    end

    it "formats nihongo template correctly" do
      expect(correct_inline_template("{{nihongo|Tokyo|東京|Tōkyō}}")).to eq "Tokyo (東京, Tōkyō)"
      expect(correct_inline_template("{{nihongo|Tokyo|東京}}")).to eq "Tokyo (東京)"
    end

    it "handles convert template" do
      expect(correct_inline_template("{{convert|100|km|mi}}")).to eq "100 km"
    end

    it "removes flag templates" do
      expect(correct_inline_template("{{flagicon|Japan}}")).to eq ""
      expect(correct_inline_template("{{JPN}}")).to eq ""
      expect(correct_inline_template("{{USA}}")).to eq ""
    end
  end
end
