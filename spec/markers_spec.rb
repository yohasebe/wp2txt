# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Wp2txt Markers" do
  include Wp2txt

  # Default behavior: markers are ON
  describe "marker replacement (default: enabled)" do
    describe "MATH marker" do
      it "replaces <math> tags with [MATH]" do
        input = "The equation <math>E = mc^2</math> is famous."
        result = format_wiki(input)
        expect(result).to include("[MATH]")
        expect(result).not_to include("<math>")
        expect(result).not_to include("E = mc^2")
      end

      it "replaces {{math}} templates with [MATH]" do
        input = "The formula {{math|x^2 + y^2 = z^2}} is well known."
        result = format_wiki(input)
        expect(result).to include("[MATH]")
        expect(result).not_to include("{{math")
      end

      it "replaces {{mvar}} templates with [MATH]" do
        input = "Let {{mvar|n}} be an integer."
        result = format_wiki(input)
        expect(result).to include("[MATH]")
      end
    end

    describe "CODE marker" do
      it "replaces <code> tags with [CODE]" do
        input = "Use <code>printf()</code> to print."
        result = format_wiki(input)
        expect(result).to include("[CODE]")
        expect(result).not_to include("<code>")
      end

      it "replaces <syntaxhighlight> tags with [CODE]" do
        input = "<syntaxhighlight lang=\"python\">def hello():\n    print('Hello')</syntaxhighlight>"
        result = format_wiki(input)
        expect(result).to include("[CODE]")
        expect(result).not_to include("<syntaxhighlight")
      end

      it "replaces <source> tags with [CODE]" do
        input = "<source lang=\"ruby\">puts 'hello'</source>"
        result = format_wiki(input)
        expect(result).to include("[CODE]")
        expect(result).not_to include("<source")
      end

      it "replaces <pre> tags with [CODE]" do
        input = "<pre>some preformatted code</pre>"
        result = format_wiki(input)
        expect(result).to include("[CODE]")
        expect(result).not_to include("<pre>")
      end
    end

    describe "CHEM marker" do
      it "replaces <chem> tags with [CHEM]" do
        input = "Water is <chem>H2O</chem>."
        result = format_wiki(input)
        expect(result).to include("[CHEM]")
        expect(result).not_to include("<chem>")
      end

      it "replaces {{chem}} templates with [CHEM]" do
        input = "The reaction produces {{chem|CO|2}}."
        result = format_wiki(input)
        expect(result).to include("[CHEM]")
      end

      it "replaces {{ce}} templates with [CHEM]" do
        input = "Salt is {{ce|NaCl}}."
        result = format_wiki(input)
        expect(result).to include("[CHEM]")
      end
    end

    describe "TABLE marker" do
      it "replaces wiki tables with [TABLE]" do
        input = "Data:\n{| class=\"wikitable\"\n|-\n! Header\n|-\n| Cell\n|}\nMore text."
        result = format_wiki(input)
        expect(result).to include("[TABLE]")
        expect(result).not_to include("{|")
        expect(result).not_to include("|}")
      end

      it "replaces <table> tags with [TABLE]" do
        input = "Data: <table><tr><td>Cell</td></tr></table> more."
        result = format_wiki(input)
        expect(result).to include("[TABLE]")
        expect(result).not_to include("<table>")
      end
    end

    describe "SCORE marker" do
      it "replaces <score> tags with [SCORE]" do
        input = "The melody: <score>\\relative c' { c d e f g }</score>"
        result = format_wiki(input)
        expect(result).to include("[SCORE]")
        expect(result).not_to include("<score>")
      end
    end

    describe "TIMELINE marker" do
      it "replaces <timeline> tags with [TIMELINE]" do
        input = "History:\n<timeline>\nImageSize = width:800\n</timeline>\nEnd."
        result = format_wiki(input)
        expect(result).to include("[TIMELINE]")
        expect(result).not_to include("<timeline>")
      end
    end

    describe "GRAPH marker" do
      it "replaces <graph> tags with [GRAPH]" do
        input = "Chart: <graph>{\"data\": []}</graph> shown above."
        result = format_wiki(input)
        expect(result).to include("[GRAPH]")
        expect(result).not_to include("<graph>")
      end
    end

    describe "IPA marker" do
      it "replaces {{IPA}} templates with [IPA]" do
        input = "Pronounced {{IPA|/həˈloʊ/}}."
        result = format_wiki(input)
        expect(result).to include("[IPA]")
      end

      it "replaces {{IPAc-en}} templates with [IPA]" do
        input = "Say {{IPAc-en|ˈ|h|ɛ|l|oʊ}}."
        result = format_wiki(input)
        expect(result).to include("[IPA]")
      end
    end

    describe "INFOBOX marker" do
      it "replaces {{Infobox}} templates with [INFOBOX]" do
        input = "{{Infobox person\n|name = John\n|birth_date = 1990\n}}\nJohn is a person."
        result = format_wiki(input)
        expect(result).to include("[INFOBOX]")
        expect(result).not_to include("{{Infobox")
        expect(result).not_to include("name = John")
      end

      it "handles nested templates in infobox" do
        input = "{{Infobox country\n|name = {{flag|Japan}}\n|capital = Tokyo\n}}"
        result = format_wiki(input)
        expect(result).to include("[INFOBOX]")
        expect(result).not_to include("{{Infobox")
      end
    end

    describe "NAVBOX marker" do
      it "replaces {{Navbox}} templates with [NAVBOX]" do
        input = "Text\n{{Navbox\n|title = Navigation\n|list1 = Item1\n}}"
        result = format_wiki(input)
        expect(result).to include("[NAVBOX]")
        expect(result).not_to include("{{Navbox")
      end
    end

    describe "GALLERY marker" do
      it "replaces <gallery> tags with [GALLERY]" do
        input = "Images:\n<gallery>\nFile:Test.jpg|Caption\nFile:Test2.jpg|Caption2\n</gallery>"
        result = format_wiki(input)
        expect(result).to include("[GALLERY]")
        expect(result).not_to include("<gallery>")
      end
    end

    describe "SIDEBAR marker" do
      it "replaces {{Sidebar}} templates with [SIDEBAR]" do
        input = "{{Sidebar\n|title = Test\n|content = Text\n}}"
        result = format_wiki(input)
        expect(result).to include("[SIDEBAR]")
        expect(result).not_to include("{{Sidebar")
      end
    end

    describe "MAPFRAME marker" do
      it "replaces <mapframe> tags with [MAPFRAME]" do
        input = "Map: <mapframe latitude=\"51.5\" longitude=\"-0.1\">data</mapframe>"
        result = format_wiki(input)
        expect(result).to include("[MAPFRAME]")
        expect(result).not_to include("<mapframe")
      end
    end

    describe "IMAGEMAP marker" do
      it "replaces <imagemap> tags with [IMAGEMAP]" do
        input = "<imagemap>\nImage:Test.png|100px\nrect 0 0 100 100 [[Link]]\n</imagemap>"
        result = format_wiki(input)
        expect(result).to include("[IMAGEMAP]")
        expect(result).not_to include("<imagemap>")
      end
    end

    describe "REFERENCES marker" do
      it "replaces {{reflist}} templates with [REFERENCES]" do
        input = "Text with citations.\n\n== References ==\n{{reflist}}"
        result = format_wiki(input)
        expect(result).to include("[REFERENCES]")
        expect(result).not_to include("{{reflist")
      end

      it "replaces {{Reflist}} with parameters with [REFERENCES]" do
        input = "== References ==\n{{Reflist|30em}}"
        result = format_wiki(input)
        expect(result).to include("[REFERENCES]")
      end

      it "replaces <references/> self-closing tag with [REFERENCES]" do
        input = "== References ==\n<references/>"
        result = format_wiki(input)
        expect(result).to include("[REFERENCES]")
        expect(result).not_to include("<references")
      end

      it "replaces <references>...</references> tag with [REFERENCES]" do
        input = "== References ==\n<references>\n<ref name=\"test\">Content</ref>\n</references>"
        result = format_wiki(input)
        expect(result).to include("[REFERENCES]")
        expect(result).not_to include("<references>")
      end

      it "replaces {{refbegin}}...{{refend}} blocks with [REFERENCES]" do
        input = "== Bibliography ==\n{{refbegin}}\n* Book one\n* Book two\n{{refend}}"
        result = format_wiki(input)
        expect(result).to include("[REFERENCES]")
        expect(result).not_to include("{{refbegin")
        expect(result).not_to include("{{refend")
        expect(result).not_to include("Book one")
      end

      it "handles {{refbegin}} with parameters" do
        input = "{{refbegin|30em|indent=yes}}\n* Citation\n{{refend}}"
        result = format_wiki(input)
        expect(result).to include("[REFERENCES]")
        expect(result).not_to include("Citation")
      end
    end

    describe "Citation extraction (extract_citations option)" do
      it "extracts author, title, year from {{cite book}}" do
        input = "{{cite book |last=Smith |first=John |title=The Book Title |year=2020}}"
        result = format_wiki(input, extract_citations: true)
        expect(result).to include("Smith")
        expect(result).to include("The Book Title")
        expect(result).to include("2020")
      end

      it "extracts from {{cite web}}" do
        input = "{{cite web |title=Web Page Title |url=http://example.com |date=2021-05-15}}"
        result = format_wiki(input, extract_citations: true)
        expect(result).to include("Web Page Title")
        expect(result).to include("2021")
      end

      it "extracts from {{cite news}}" do
        input = "{{cite news |last=Reporter |title=News Article |newspaper=Daily News |date=2022-03-20}}"
        result = format_wiki(input, extract_citations: true)
        expect(result).to include("Reporter")
        expect(result).to include("News Article")
        expect(result).to include("2022")
      end

      it "extracts from {{cite journal}}" do
        input = "{{cite journal |last=Scientist |title=Research Paper |journal=Nature |year=2023}}"
        result = format_wiki(input, extract_citations: true)
        expect(result).to include("Scientist")
        expect(result).to include("Research Paper")
        expect(result).to include("2023")
      end

      it "extracts from {{Citation}}" do
        input = "{{Citation |last=Doe |first=Jane |title=Article Title |year=2019 |publisher=Publisher Name}}"
        result = format_wiki(input, extract_citations: true)
        expect(result).to include("Doe")
        expect(result).to include("Article Title")
        expect(result).to include("2019")
      end

      it "handles multiple citations" do
        input = "* {{cite book |last=Author1 |title=Book One |year=2001}}\n* {{cite book |last=Author2 |title=Book Two |year=2002}}"
        result = format_wiki(input, extract_citations: true)
        expect(result).to include("Author1")
        expect(result).to include("Book One")
        expect(result).to include("Author2")
        expect(result).to include("Book Two")
      end

      it "extracts citations from refbegin/refend blocks" do
        input = "{{refbegin}}\n* {{cite book |last=Smith |title=Book Title |year=2020}}\n{{refend}}"
        result = format_wiki(input, extract_citations: true)
        expect(result).to include("Smith")
        expect(result).to include("Book Title")
        expect(result).not_to include("{{refbegin")
        expect(result).not_to include("{{refend")
      end

      it "removes citations when extract_citations is false (default)" do
        input = "Text. {{cite book |last=Smith |title=Book |year=2020}}"
        result = format_wiki(input)
        expect(result).not_to include("Smith")
        expect(result).not_to include("Book")
      end

      it "handles citations with only title" do
        input = "{{cite web |title=Untitled Page |url=http://example.com}}"
        result = format_wiki(input, extract_citations: true)
        expect(result).to include("Untitled Page")
      end

      it "handles author1/first1 format" do
        input = "{{cite book |last1=Primary |first1=Author |title=Multi-Author Book |year=2021}}"
        result = format_wiki(input, extract_citations: true)
        expect(result).to include("Primary")
        expect(result).to include("Multi-Author Book")
      end
    end
  end

  # Markers can be disabled
  describe "marker replacement (disabled)" do
    it "removes content without markers when markers disabled" do
      input = "The equation <math>E = mc^2</math> is famous."
      result = format_wiki(input, markers: false)
      expect(result).not_to include("[MATH]")
      expect(result).not_to include("<math>")
      expect(result).not_to include("E = mc^2")
    end

    it "removes all marker types when disabled" do
      input = "<code>x</code> <chem>H2O</chem> <score>notes</score>"
      result = format_wiki(input, markers: false)
      expect(result).not_to include("[CODE]")
      expect(result).not_to include("[CHEM]")
      expect(result).not_to include("[SCORE]")
    end

    it "removes infobox when markers disabled" do
      input = "{{Infobox person\n|name = John\n}}\nText."
      result = format_wiki(input, markers: false)
      expect(result).not_to include("[INFOBOX]")
      expect(result).not_to include("{{Infobox")
      expect(result).to include("Text")
    end

    it "removes navbox when markers disabled" do
      input = "Text.\n{{Navbox\n|title = Nav\n}}"
      result = format_wiki(input, markers: false)
      expect(result).not_to include("[NAVBOX]")
      expect(result).not_to include("{{Navbox")
    end

    it "removes gallery when markers disabled" do
      input = "<gallery>\nFile:Test.jpg\n</gallery>"
      result = format_wiki(input, markers: false)
      expect(result).not_to include("[GALLERY]")
      expect(result).not_to include("<gallery>")
    end

    it "removes references when markers disabled" do
      input = "Text.\n{{reflist}}"
      result = format_wiki(input, markers: false)
      expect(result).not_to include("[REFERENCES]")
      expect(result).not_to include("{{reflist")
    end
  end

  # Selective markers
  describe "selective marker replacement" do
    it "enables only specified markers" do
      input = "<math>x</math> and <code>y</code>"
      result = format_wiki(input, markers: [:math])
      expect(result).to include("[MATH]")
      expect(result).not_to include("[CODE]")
      expect(result).not_to include("<code>")
    end

    it "accepts array of marker symbols" do
      input = "<math>x</math> <code>y</code> <chem>H2O</chem>"
      result = format_wiki(input, markers: [:math, :code])
      expect(result).to include("[MATH]")
      expect(result).to include("[CODE]")
      expect(result).not_to include("[CHEM]")
    end
  end

  # Multiple markers in one text
  describe "multiple markers" do
    it "handles multiple marker types in same text" do
      input = "Formula <math>E=mc^2</math>, code <code>x=1</code>, and water <chem>H2O</chem>."
      result = format_wiki(input)
      expect(result).to include("[MATH]")
      expect(result).to include("[CODE]")
      expect(result).to include("[CHEM]")
    end

    it "handles nested content correctly" do
      input = "{| class=\"wikitable\"\n|-\n| <math>x^2</math>\n|}"
      result = format_wiki(input)
      expect(result).to include("[TABLE]")
      # Math inside table is processed with the table
    end
  end
end
