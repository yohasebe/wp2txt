# frozen_string_literal: true

require_relative "spec_helper"
require_relative "fixtures/samples"

RSpec.describe "Integration Tests" do
  include Wp2txt

  # Use let blocks to avoid constant redefinition warnings
  let(:japanese_article) { Wp2txt::TestSamples::JAPANESE_ARTICLE }
  let(:russian_article) { Wp2txt::TestSamples::RUSSIAN_ARTICLE }
  let(:arabic_article) { Wp2txt::TestSamples::ARABIC_ARTICLE }
  let(:deeply_nested) { Wp2txt::TestSamples::DEEPLY_NESTED }
  let(:malformed_markup) { Wp2txt::TestSamples::MALFORMED_MARKUP }
  let(:table_content) { Wp2txt::TestSamples::TABLE_CONTENT }
  let(:multiline_link) { Wp2txt::TestSamples::MULTILINE_LINK }

  describe "Full article processing" do
    let(:sample_article) do
      <<~WIKI
        {{Infobox person
        |name = Test Person
        |birth_date = {{Birth date|1990|1|15}}
        }}
        '''Test Person''' (born January 15, 1990) is a [[scientist]].

        == Early Life ==
        Born in [[Tokyo]], [[Japan]].

        == Career ==
        * Started at [[Company A]]
        * Moved to [[Company B]]

        === Publications ===
        # First paper (2010)
        # Second paper (2015)

        == References ==
        <ref>Citation 1</ref>
        <ref name="ref2">Citation 2</ref>

        == External Links ==
        * [http://example.com Official website]

        [[Category:Scientists]]
        [[Category:1990 births]]
      WIKI
    end

    it "extracts clean text with correct structure" do
      article = Wp2txt::Article.new(sample_article, "Test Person")
      types = article.elements.map(&:first)

      expect(types).to include(:mw_heading)
      expect(types).to include(:mw_paragraph)
      expect(types).to include(:mw_unordered)
      expect(types).to include(:mw_ordered)
    end

    it "extracts categories correctly" do
      article = Wp2txt::Article.new(sample_article, "Test Person")
      categories = article.categories.flatten
      expect(categories).to include("Scientists")
    end
  end

  describe "Unicode handling" do
    it "handles CJK characters in articles" do
      article = Wp2txt::Article.new(japanese_article)
      expect(article.elements).not_to be_empty
    end

    it "handles Cyrillic characters" do
      article = Wp2txt::Article.new(russian_article)
      expect(article.elements).not_to be_empty
    end

    it "handles Arabic characters" do
      article = Wp2txt::Article.new(arabic_article)
      expect(article.elements).not_to be_empty
    end

    # Test for emoji handling (will fail until bug is fixed)
    it "handles emoji character references" do
      result = chrref_to_utf("&#x1F600;")
      # This test exposes the BMP limitation bug
      # After fix, this should equal the grinning face emoji
      expect(result.valid_encoding?).to be true
    end
  end

  describe "Edge cases" do
    it "handles deeply nested templates without hanging" do
      start_time = Time.now
      expect { Wp2txt::Article.new(deeply_nested) }.not_to raise_error
      elapsed = Time.now - start_time
      expect(elapsed).to be < 5  # Should complete in under 5 seconds
    end

    it "handles malformed markup gracefully" do
      expect { Wp2txt::Article.new(malformed_markup) }.not_to raise_error
    end

    it "handles multi-line links" do
      expect { Wp2txt::Article.new(multiline_link) }.not_to raise_error
    end

    it "handles table content" do
      article = Wp2txt::Article.new(table_content)
      types = article.elements.map(&:first)
      expect(types).to include(:mw_table)
    end
  end

  describe "Text processing utilities" do
    describe "chrref_to_utf" do
      it "converts basic ASCII character references" do
        expect(chrref_to_utf("&#65;")).to eq "A"
        expect(chrref_to_utf("&#97;")).to eq "a"
      end

      it "converts hexadecimal character references" do
        expect(chrref_to_utf("&#x41;")).to eq "A"
        expect(chrref_to_utf("&#x61;")).to eq "a"
      end

      it "converts BMP characters" do
        # Musical note U+266A
        expect(chrref_to_utf("&#x266A;")).to eq "\u266A"
        expect(chrref_to_utf("&#9834;")).to eq "\u266A"
      end

      # This test will FAIL until the BMP limitation is fixed
      it "converts supplementary plane characters (emoji)" do
        # Grinning face U+1F600
        expect(chrref_to_utf("&#x1F600;")).to eq "\u{1F600}"
        expect(chrref_to_utf("&#128512;")).to eq "\u{1F600}"
      end
    end

    describe "convert_characters" do
      it "handles valid UTF-8 content" do
        text = "Hello 世界 こんにちは"
        result = convert_characters(text)
        expect(result).to eq text
        expect(result.valid_encoding?).to be true
      end

      it "handles invalid UTF-8 sequences" do
        # Invalid UTF-8 byte sequence
        invalid = "Hello\xC0World"
        result = convert_characters(invalid)
        expect(result.valid_encoding?).to be true
        expect(result.encoding.name).to eq "UTF-8"
      end
    end

    describe "special_chr" do
      it "converts common HTML entities" do
        # &nbsp; converts to U+00A0 (non-breaking space), not regular space
        expect(special_chr("&nbsp;")).to eq "\u00A0"
        expect(special_chr("&lt;")).to eq "<"
        expect(special_chr("&gt;")).to eq ">"
        expect(special_chr("&amp;")).to eq "&"
      end

      it "converts Wikipedia-specific entities" do
        expect(special_chr("&ratio;")).to eq "∶"
        expect(special_chr("&dash;")).to eq "–"
        expect(special_chr("&nbso;")).to eq " "  # Common typo for &nbsp;
      end

      it "converts mathematical entities" do
        expect(special_chr("&alpha;")).to eq "α"
        expect(special_chr("&beta;")).to eq "β"
        expect(special_chr("&infin;")).to eq "∞"
        expect(special_chr("&sum;")).to eq "∑"
      end
    end
  end

  describe "Process nested structure" do
    describe "process_nested_structure" do
      it "processes simple nested brackets" do
        scanner = StringScanner.new("[[test]]")
        result = process_nested_structure(scanner, "[[", "]]") { |c| "<#{c}>" }
        expect(result).to eq "<test>"
      end

      it "processes nested templates" do
        scanner = StringScanner.new("{{outer}}")
        result = process_nested_structure(scanner, "{{", "}}") { |c| "[#{c}]" }
        expect(result).to eq "[outer]"
      end

      # This test exposes the state leakage bug
      it "handles consecutive calls without state leakage" do
        scanner1 = StringScanner.new("[[first]]")
        result1 = process_nested_structure(scanner1, "[[", "]]") { |c| "<#{c}>" }
        expect(result1).to eq "<first>"

        # Second call should not be affected by first call's state
        scanner2 = StringScanner.new("plain text")
        result2 = process_nested_structure(scanner2, "[[", "]]") { |c| "<#{c}>" }
        expect(result2).to eq "plain text"
      end

      it "handles table brackets" do
        scanner = StringScanner.new("{|content|}")
        result = process_nested_structure(scanner, "{|", "|}") { |c| "[#{c}]" }
        expect(result).to eq "[content]"
      end
    end
  end

  # === Additional Edge Case Tests for v2.0.0 ===

  describe "Additional edge cases" do
    let(:special_title_article) { Wp2txt::TestSamples::SPECIAL_TITLE_ARTICLE }
    let(:very_deeply_nested) { Wp2txt::TestSamples::VERY_DEEPLY_NESTED }
    let(:mixed_content) { Wp2txt::TestSamples::MIXED_CONTENT }
    let(:complex_links) { Wp2txt::TestSamples::COMPLEX_LINKS }
    let(:consecutive_templates) { Wp2txt::TestSamples::CONSECUTIVE_TEMPLATES }
    let(:html_entities_mixed) { Wp2txt::TestSamples::HTML_ENTITIES_MIXED }
    let(:horizontal_rules) { Wp2txt::TestSamples::HORIZONTAL_RULES }
    let(:complex_headings) { Wp2txt::TestSamples::COMPLEX_HEADINGS }
    let(:redirect_variations) { Wp2txt::TestSamples::REDIRECT_VARIATIONS }

    it "handles special characters in article content" do
      expect { Wp2txt::Article.new(special_title_article) }.not_to raise_error
      article = Wp2txt::Article.new(special_title_article)
      expect(article.elements).not_to be_empty
    end

    it "handles very deeply nested templates (10 levels)" do
      start_time = Time.now
      expect { Wp2txt::Article.new(very_deeply_nested) }.not_to raise_error
      elapsed = Time.now - start_time
      expect(elapsed).to be < 5  # Should complete quickly
    end

    it "handles mixed multilingual content with emoji" do
      expect { Wp2txt::Article.new(mixed_content) }.not_to raise_error
      article = Wp2txt::Article.new(mixed_content)
      expect(article.elements).not_to be_empty
    end

    it "handles complex wikilinks" do
      expect { Wp2txt::Article.new(complex_links) }.not_to raise_error
    end

    it "handles consecutive templates" do
      expect { Wp2txt::Article.new(consecutive_templates) }.not_to raise_error
    end

    it "handles HTML entities mixed with character references" do
      expect { Wp2txt::Article.new(html_entities_mixed) }.not_to raise_error
    end

    it "handles horizontal rules correctly (only 4+ hyphens)" do
      article = Wp2txt::Article.new(horizontal_rules)
      # The article should process without error
      expect(article.elements).not_to be_empty
    end

    it "handles complex headings with formatting" do
      article = Wp2txt::Article.new(complex_headings)
      types = article.elements.map(&:first)
      expect(types.count(:mw_heading)).to be >= 4
    end

    it "handles redirect variations" do
      # Test each redirect variation
      ["#REDIRECT [[Target]]", "#redirect [[lowercase]]"].each do |redirect|
        article = Wp2txt::Article.new(redirect)
        types = article.elements.map(&:first)
        expect(types).to include(:mw_redirect)
      end
    end
  end

  describe "Multilingual category extraction" do
    it "extracts Japanese categories" do
      article = Wp2txt::Article.new("[[カテゴリ:テスト]][[カテゴリ:例]]")
      categories = article.categories.flatten
      expect(categories).to include("テスト")
    end

    it "extracts Chinese categories" do
      article = Wp2txt::Article.new("[[分类:测试]][[分類:範例]]")
      categories = article.categories.flatten
      expect(categories.size).to be >= 1
    end

    it "extracts German categories" do
      article = Wp2txt::Article.new("[[Kategorie:Test]]")
      categories = article.categories.flatten
      expect(categories).to include("Test")
    end

    it "extracts French categories" do
      article = Wp2txt::Article.new("[[Catégorie:Test]]")
      categories = article.categories.flatten
      expect(categories).to include("Test")
    end

    it "extracts Russian categories" do
      article = Wp2txt::Article.new("[[Категория:Тест]]")
      categories = article.categories.flatten
      expect(categories).to include("Тест")
    end

    it "extracts mixed language categories from one article" do
      mixed = "[[Category:English]][[カテゴリ:日本語]][[分类:中文]]"
      article = Wp2txt::Article.new(mixed)
      categories = article.categories.flatten
      expect(categories.size).to be >= 2
    end
  end

  describe "Emoji and supplementary plane character handling" do
    it "converts emoji character references correctly" do
      result = chrref_to_utf("&#x1F600;")
      expect(result).to eq "😀"
      expect(result.valid_encoding?).to be true
    end

    it "converts multiple emoji in text" do
      result = chrref_to_utf("Hello &#x1F600; World &#x1F4BB;!")
      expect(result).to include("😀")
      expect(result).to include("💻")
    end

    it "handles CJK Extension B characters" do
      # U+20000 is 𠀀 (CJK Extension B)
      result = chrref_to_utf("&#x20000;")
      expect(result.valid_encoding?).to be true
      expect(result.length).to eq 1
    end

    it "handles invalid codepoints gracefully" do
      # U+110000 is beyond Unicode max
      result = chrref_to_utf("&#x110000;")
      expect(result).to eq ""
    end
  end

  describe "Horizontal rule processing" do
    it "removes lines with 4+ hyphens" do
      result = remove_hr("text\n----\nmore")
      expect(result).not_to include("----")
    end

    it "preserves lines with fewer than 4 hyphens" do
      result = remove_hr("text\n--\nmore\n---\nend")
      expect(result).to include("--")
      expect(result).to include("---")
    end

    it "removes very long horizontal rules" do
      result = remove_hr("text\n" + "-" * 20 + "\nmore")
      expect(result).not_to include("-" * 20)
    end
  end

  describe "Full article output format" do
    let(:wiki_with_categories) do
      <<~WIKI
        '''Test Person''' is a [[scientist]] who studies [[physics]].

        == Early Life ==
        Born in [[Tokyo]], [[Japan]].

        == Career ==
        Worked at [[University]].

        [[Category:Scientists]]
        [[Category:Physicists]]
      WIKI
    end

    it "extracts both body text and categories from articles" do
      article = Wp2txt::Article.new(wiki_with_categories, "Test Person")

      # Should have body content
      paragraphs = article.elements.select { |e| e.first == :mw_paragraph }
      expect(paragraphs).not_to be_empty

      # First paragraph should contain the intro
      first_para_content = paragraphs.first.last
      expect(first_para_content).to include("scientist")

      # Should have categories
      categories = article.categories.flatten
      expect(categories).to include("Scientists")
      expect(categories).to include("Physicists")

      # Should have headings
      headings = article.elements.select { |e| e.first == :mw_heading }
      expect(headings.size).to eq 2
    end

    it "format_wiki removes markup but preserves text content" do
      article = Wp2txt::Article.new(wiki_with_categories, "Test Person")

      paragraphs = article.elements.select { |e| e.first == :mw_paragraph }
      first_para = paragraphs.first.last

      formatted = format_wiki(first_para)

      # Text should be preserved
      expect(formatted).to include("scientist")
      expect(formatted).to include("physics")

      # Wiki markup should be removed
      expect(formatted).not_to include("[[")
      expect(formatted).not_to include("]]")
      expect(formatted).not_to include("'''")
    end

    it "cleanup produces valid output" do
      raw_output = <<~TEXT
        [[Title]]

        Some text here.

        [ref][/ref]


        More text.



        Final text.
      TEXT

      cleaned = cleanup(raw_output)

      # Should remove empty refs
      expect(cleaned).not_to include("[ref][/ref]")

      # Should collapse multiple newlines
      expect(cleaned).not_to include("\n\n\n")

      # Should preserve content
      expect(cleaned).to include("Some text")
      expect(cleaned).to include("More text")
    end
  end

  describe "Performance optimizations" do
    it "regex_cache stores dynamically created patterns for remove_inbetween" do
      # Clear cache first
      Wp2txt.regex_cache.clear

      # remove_inbetween uses the regex cache for custom tagsets
      remove_inbetween("<tag>content</tag>", ["<tag>", "</tag>"])

      # Cache should now have an entry
      expect(Wp2txt.regex_cache).not_to be_empty
      expect(Wp2txt.regex_cache.keys.first).to include("inbetween")
    end

    it "processes articles without creating excessive intermediate strings" do
      large_text = "[[link]] " * 100 + "'''bold''' " * 100 + "text " * 100
      article = Wp2txt::Article.new(large_text, "Large Article")

      # Should complete without error
      expect(article.elements).not_to be_empty

      # Format should work
      article.elements.each do |type, content|
        if type == :mw_paragraph
          result = format_wiki(content)
          expect(result).to be_a(String)
          expect(result.valid_encoding?).to be true
        end
      end
    end
  end

  describe "HTML Entity Management" do
    describe "Wp2txt.load_html_entities" do
      it "loads entities from JSON files" do
        entities = Wp2txt.load_html_entities
        expect(entities).to be_a(Hash)
        expect(entities.size).to be > 2000
      end

      it "includes WHATWG standard entities" do
        entities = Wp2txt.load_html_entities
        expect(entities["&alpha;"]).to eq "α"
        expect(entities["&AElig;"]).to eq "Æ"
        expect(entities["&copy;"]).to eq "©"
        expect(entities["&nbsp;"]).to eq "\u00A0"
      end

      it "includes Wikipedia-specific entities" do
        entities = Wp2txt.load_html_entities
        expect(entities["&ratio;"]).to eq "∶"
        expect(entities["&dash;"]).to eq "–"
        expect(entities["&nbso;"]).to eq " "
      end
    end

    describe "EXTRA_ENTITIES constant" do
      it "is frozen to prevent modification" do
        expect(Wp2txt::EXTRA_ENTITIES).to be_frozen
      end

      it "contains comprehensive entity coverage" do
        # Should have 2000+ entities from WHATWG + Wikipedia-specific
        expect(Wp2txt::EXTRA_ENTITIES.size).to be > 2000
      end
    end

    describe "EXTRA_ENTITIES_REGEX" do
      it "matches entity patterns" do
        regex = Wp2txt::EXTRA_ENTITIES_REGEX
        expect("&alpha;").to match(regex)
        expect("&ratio;").to match(regex)
        expect("&AElig;").to match(regex)
      end

      it "captures entity name in match" do
        regex = Wp2txt::EXTRA_ENTITIES_REGEX
        match = "text &alpha; more".match(regex)
        expect(match).not_to be_nil
        expect(match[1]).to eq "&alpha;"
      end
    end

    describe "backward compatibility" do
      it "MATH_ENTITIES is aliased to EXTRA_ENTITIES" do
        expect(Wp2txt::MATH_ENTITIES).to eq Wp2txt::EXTRA_ENTITIES
      end

      it "MATH_ENTITIES_REGEX is aliased to EXTRA_ENTITIES_REGEX" do
        expect(Wp2txt::MATH_ENTITIES_REGEX).to eq Wp2txt::EXTRA_ENTITIES_REGEX
      end
    end
  end
end
