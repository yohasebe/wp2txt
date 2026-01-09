# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Wp2txt Text Processing" do
  include Wp2txt

  describe "convert_characters" do
    it "handles valid UTF-8 text" do
      result = convert_characters("Hello World")
      expect(result).to eq("Hello World")
    end

    it "handles Unicode text" do
      result = convert_characters("日本語テキスト")
      expect(result).to eq("日本語テキスト")
    end

    it "converts HTML entities" do
      result = convert_characters("Hello &amp; World")
      expect(result).to eq("Hello & World")
    end

    it "handles nil input" do
      result = convert_characters(nil)
      expect(result).to eq("")
    end

    it "handles numeric character references" do
      result = convert_characters("&#65;&#66;&#67;")
      expect(result).to eq("ABC")
    end
  end

  describe "special_chr" do
    it "decodes HTML entities" do
      result = special_chr("&amp; &lt; &gt;")
      expect(result).to eq("& < >")
    end

    it "decodes special quotes" do
      result = special_chr("&ldquo;text&rdquo;")
      expect(result).to include("text")
    end
  end

  describe "chrref_to_utf" do
    it "converts decimal character references" do
      result = chrref_to_utf("&#65;")
      expect(result).to eq("A")
    end

    it "converts hex character references" do
      result = chrref_to_utf("&#x41;")
      expect(result).to eq("A")
    end

    it "handles Japanese characters" do
      result = chrref_to_utf("&#12354;")
      expect(result).to eq("あ")
    end

    it "handles invalid codepoints" do
      result = chrref_to_utf("&#0;")
      expect(result).to eq("")
    end

    it "preserves non-reference text" do
      result = chrref_to_utf("normal text")
      expect(result).to eq("normal text")
    end
  end

  describe "mndash" do
    it "converts ndash template" do
      result = mndash("1990{{ndash}}2000")
      # The implementation wraps the dash in braces
      expect(result).to include("–")
    end

    it "handles mdash" do
      result = mndash("text{{mdash}}more")
      expect(result).to include("–")
    end

    it "preserves text without dashes" do
      result = mndash("normal text")
      expect(result).to eq("normal text")
    end
  end

  describe "process_nested_structure" do
    it "processes simple nested brackets" do
      result = process_nested_structure("[[test]]", "[[", "]]") do |content|
        content.upcase
      end
      expect(result).to eq("TEST")
    end

    it "processes multiple nested levels" do
      result = process_nested_structure("[[outer [[inner]]]]", "[[", "]]") do |content|
        "[#{content}]"
      end
      # The algorithm processes innermost first, then outer
      expect(result).to include("[inner]")
    end

    it "handles empty content" do
      result = process_nested_structure("[[]]", "[[", "]]") do |_content|
        "empty"
      end
      expect(result).to eq("empty")
    end

    it "preserves text without brackets" do
      result = process_nested_structure("no brackets here", "[[", "]]") do |_content|
        "replaced"
      end
      expect(result).to eq("no brackets here")
    end

    it "handles curly braces" do
      result = process_nested_structure("{{template}}", "{{", "}}") do |content|
        "T:#{content}"
      end
      expect(result).to eq("T:template")
    end
  end

  describe "escape_nowiki and unescape_nowiki" do
    it "escapes and unescapes nowiki tags" do
      original = "text <nowiki>[[preserved]]</nowiki> more"
      escaped = escape_nowiki(original)
      expect(escaped).not_to include("[[preserved]]")
      expect(escaped).to include("<nowiki-")

      unescaped = unescape_nowiki(escaped)
      expect(unescaped).to include("[[preserved]]")
    end

    it "handles multiple nowiki tags" do
      original = "<nowiki>a</nowiki> and <nowiki>b</nowiki>"
      escaped = escape_nowiki(original)
      expect(escaped.scan(/<nowiki-\d+>/).size).to eq(2)
    end
  end

  describe "cleanup" do
    it "removes excessive newlines" do
      result = cleanup("text\n\n\n\n\nmore")
      expect(result.count("\n")).to be <= 4  # max 2 consecutive + trailing
    end

    it "removes empty parentheses" do
      result = cleanup("text () more")
      expect(result).not_to include("()")
    end

    it "removes empty Japanese parentheses" do
      result = cleanup("text（）more")
      expect(result).not_to include("（）")
    end

    it "adds trailing newlines" do
      result = cleanup("text")
      expect(result).to end_with("\n\n")
    end

    it "strips leading/trailing whitespace" do
      result = cleanup("  text  ")
      expect(result).to start_with("text")
    end
  end

  describe "remove_html" do
    it "removes HTML comments" do
      result = remove_html("before <!-- comment --> after")
      expect(result).to include("before")
      expect(result).to include("after")
      expect(result).not_to include("comment")
    end

    it "removes self-closing tags" do
      result = remove_html("text<br/>more")
      expect(result).to eq("textmore")
    end

    it "removes gallery tags" do
      result = remove_html("<gallery>image.jpg</gallery>")
      expect(result).not_to include("image.jpg")
    end

    it "handles nested div tags" do
      result = remove_html("<div><div>inner</div></div>outside")
      expect(result).to eq("outside")
    end
  end

  describe "remove_complex" do
    it "converts ruby annotations" do
      # Ruby annotation: {{Ruby|漢字|かんじ}} style patterns
      result = remove_complex("text{{Ruby|漢字|かんじ}}more")
      # Should convert to 《》 format
      expect(result).to include("漢字")
    end
  end

  describe "remove_inbetween" do
    it "removes content between angle brackets" do
      result = remove_inbetween("before <tag> after")
      expect(result).to eq("before  after")
    end

    it "removes multiple occurrences" do
      result = remove_inbetween("a<1>b<2>c")
      expect(result).to eq("abc")
    end

    it "uses custom tagset" do
      result = remove_inbetween("before [content] after", ["[", "]"])
      expect(result).to eq("before  after")
    end
  end

  describe "remove_tag" do
    it "removes HTML tags" do
      result = remove_tag("<p>content</p>")
      expect(result).to eq("content")
    end

    it "removes inline tags" do
      result = remove_tag("<b>bold</b> and <i>italic</i>")
      expect(result).to eq("bold and italic")
    end
  end

  describe "remove_directive" do
    it "removes behavior switches" do
      result = remove_directive("__NOTOC__text")
      expect(result).to eq("text")
    end

    it "removes TOC directive" do
      result = remove_directive("before__TOC__after")
      expect(result).to eq("beforeafter")
    end
  end

  describe "remove_emphasis" do
    it "removes bold markup" do
      result = remove_emphasis("'''bold''' text")
      expect(result).to include("bold")
      expect(result).not_to include("'''")
    end

    it "removes italic markup" do
      result = remove_emphasis("''italic'' text")
      expect(result).to include("italic")
      expect(result).not_to include("''")
    end

    it "removes bold-italic markup" do
      result = remove_emphasis("'''''both''''' text")
      expect(result).to include("both")
      expect(result).not_to include("'''''")
    end
  end

  describe "remove_hr" do
    it "removes horizontal rules" do
      result = remove_hr("before\n----\nafter")
      expect(result).not_to include("----")
    end

    it "removes longer rules" do
      result = remove_hr("text\n------\nmore")
      expect(result).not_to include("------")
    end
  end

  describe "remove_ref" do
    # remove_ref removes [ref]...[/ref] markers (not HTML <ref> tags)
    # Use make_reference first to convert <ref> to [ref]
    it "removes [ref] marker tags" do
      result = remove_ref("text[ref]citation[/ref]more")
      expect(result).to eq("textmore")
    end

    it "removes multiple [ref] markers" do
      result = remove_ref("a[ref]1[/ref]b[ref]2[/ref]c")
      expect(result).to eq("abc")
    end

    it "preserves text without markers" do
      result = remove_ref("text without references")
      expect(result).to eq("text without references")
    end
  end

  describe "make_reference" do
    it "converts reference tags to markers" do
      result = make_reference("text<ref>citation</ref>more")
      expect(result).to include("[ref]")
      expect(result).to include("[/ref]")
    end

    it "handles multiple references" do
      result = make_reference("a<ref>1</ref>b<ref>2</ref>c")
      expect(result.scan("[ref]").size).to eq(2)
    end
  end
end
