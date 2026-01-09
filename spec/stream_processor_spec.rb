# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Wp2txt::StreamProcessor do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#each_page" do
    context "with XML file input" do
      let(:xml_content) do
        <<~XML
          <mediawiki>
            <page>
              <title>Test Article</title>
              <revision>
                <text>This is the article content.</text>
              </revision>
            </page>
            <page>
              <title>Second Article</title>
              <revision>
                <text>Second article content.</text>
              </revision>
            </page>
          </mediawiki>
        XML
      end

      let(:xml_file) { File.join(temp_dir, "test.xml") }

      before do
        File.write(xml_file, xml_content)
      end

      it "extracts pages from XML file" do
        processor = described_class.new(xml_file)
        pages = processor.each_page.to_a

        expect(pages.size).to eq(2)
        expect(pages[0][0]).to eq("Test Article")
        expect(pages[0][1]).to include("article content")
        expect(pages[1][0]).to eq("Second Article")
      end

      it "yields title and text for each page" do
        processor = described_class.new(xml_file)
        titles = []
        texts = []

        processor.each_page do |title, text|
          titles << title
          texts << text
        end

        expect(titles).to eq(["Test Article", "Second Article"])
        expect(texts[0]).to include("article content")
      end
    end

    context "with directory input" do
      let(:xml_content1) do
        <<~XML
          <page>
            <title>Article One</title>
            <revision>
              <text>Content one.</text>
            </revision>
          </page>
        XML
      end

      let(:xml_content2) do
        <<~XML
          <page>
            <title>Article Two</title>
            <revision>
              <text>Content two.</text>
            </revision>
          </page>
        XML
      end

      before do
        File.write(File.join(temp_dir, "part1.xml"), xml_content1)
        File.write(File.join(temp_dir, "part2.xml"), xml_content2)
      end

      it "processes all XML files in directory" do
        processor = described_class.new(temp_dir)
        pages = processor.each_page.to_a

        expect(pages.size).to eq(2)
        titles = pages.map(&:first)
        expect(titles).to include("Article One", "Article Two")
      end
    end

    context "with special pages" do
      let(:xml_content) do
        <<~XML
          <page>
            <title>Normal Article</title>
            <revision>
              <text>Normal content.</text>
            </revision>
          </page>
          <page>
            <title>Wikipedia:Help</title>
            <revision>
              <text>Help content.</text>
            </revision>
          </page>
          <page>
            <title>File:Image.jpg</title>
            <revision>
              <text>File description.</text>
            </revision>
          </page>
        XML
      end

      let(:xml_file) { File.join(temp_dir, "test.xml") }

      before do
        File.write(xml_file, xml_content)
      end

      it "skips pages with colon in title (special pages)" do
        processor = described_class.new(xml_file)
        pages = processor.each_page.to_a

        expect(pages.size).to eq(1)
        expect(pages[0][0]).to eq("Normal Article")
      end
    end

    context "with HTML comments" do
      let(:xml_content) do
        <<~XML
          <page>
            <title>Article With Comments</title>
            <revision>
              <text>Before <!-- hidden comment --> after.</text>
            </revision>
          </page>
        XML
      end

      let(:xml_file) { File.join(temp_dir, "test.xml") }

      before do
        File.write(xml_file, xml_content)
      end

      it "removes HTML comments from text" do
        processor = described_class.new(xml_file)
        pages = processor.each_page.to_a

        expect(pages[0][1]).not_to include("hidden comment")
        expect(pages[0][1]).to include("Before")
        expect(pages[0][1]).to include("after")
      end
    end

    context "returns enumerator when no block given" do
      let(:xml_content) do
        <<~XML
          <page>
            <title>Test</title>
            <revision>
              <text>Content.</text>
            </revision>
          </page>
        XML
      end

      let(:xml_file) { File.join(temp_dir, "test.xml") }

      before do
        File.write(xml_file, xml_content)
      end

      it "returns an Enumerator" do
        processor = described_class.new(xml_file)
        result = processor.each_page

        expect(result).to be_an(Enumerator)
        expect(result.to_a.size).to eq(1)
      end
    end

    context "with unsupported format" do
      let(:unsupported_file) { File.join(temp_dir, "test.txt") }

      before do
        File.write(unsupported_file, "plain text content")
      end

      it "raises ArgumentError for unsupported format" do
        processor = described_class.new(unsupported_file)
        expect { processor.each_page.to_a }.to raise_error(ArgumentError, /Unsupported input format/)
      end
    end

    context "with malformed XML" do
      let(:xml_content) do
        <<~XML
          <page>
            <title>Test Article</title>
            <revision>
              <text>Content with unclosed tag <b>
            </revision>
          </page>
        XML
      end

      let(:xml_file) { File.join(temp_dir, "malformed.xml") }

      before do
        File.write(xml_file, xml_content)
      end

      it "skips malformed XML gracefully" do
        processor = described_class.new(xml_file)
        pages = processor.each_page.to_a
        # Should not raise error, just skip malformed page
        expect(pages).to be_an(Array)
      end
    end

    context "with empty text node" do
      let(:xml_content) do
        <<~XML
          <page>
            <title>Empty Article</title>
            <revision>
              <text></text>
            </revision>
          </page>
        XML
      end

      let(:xml_file) { File.join(temp_dir, "empty.xml") }

      before do
        File.write(xml_file, xml_content)
      end

      it "handles empty text" do
        processor = described_class.new(xml_file)
        pages = processor.each_page.to_a
        expect(pages.size).to eq(1)
        expect(pages[0][1]).to eq("")
      end
    end

    context "with missing title" do
      let(:xml_content) do
        <<~XML
          <page>
            <revision>
              <text>Content without title.</text>
            </revision>
          </page>
        XML
      end

      let(:xml_file) { File.join(temp_dir, "no_title.xml") }

      before do
        File.write(xml_file, xml_content)
      end

      it "skips pages without title" do
        processor = described_class.new(xml_file)
        pages = processor.each_page.to_a
        expect(pages).to be_empty
      end
    end

    context "with multi-line HTML comments" do
      let(:xml_content) do
        <<~XML
          <page>
            <title>Multi Comment Article</title>
            <revision>
              <text>Before
          <!--
          Multi-line
          comment
          here
          -->
          After</text>
            </revision>
          </page>
        XML
      end

      let(:xml_file) { File.join(temp_dir, "multiline_comment.xml") }

      before do
        File.write(xml_file, xml_content)
      end

      it "preserves newline count from multi-line comments" do
        processor = described_class.new(xml_file)
        pages = processor.each_page.to_a
        expect(pages.size).to eq(1)
        text = pages[0][1]
        expect(text).not_to include("Multi-line")
        expect(text).not_to include("comment")
        # Check that newlines are preserved (original content has newlines)
        expect(text.count("\n")).to be >= 1
      end
    end

    context "with multiple pages in buffer" do
      let(:xml_content) do
        (1..10).map do |i|
          <<~XML
            <page>
              <title>Article #{i}</title>
              <revision>
                <text>Content for article #{i}.</text>
              </revision>
            </page>
          XML
        end.join("\n")
      end

      let(:xml_file) { File.join(temp_dir, "many_pages.xml") }

      before do
        File.write(xml_file, xml_content)
      end

      it "processes all pages correctly" do
        processor = described_class.new(xml_file)
        pages = processor.each_page.to_a
        expect(pages.size).to eq(10)
        expect(pages.map(&:first)).to eq((1..10).map { |i| "Article #{i}" })
      end
    end
  end

  describe "#initialize" do
    it "accepts input path" do
      processor = described_class.new("/path/to/file.xml")
      expect(processor.instance_variable_get(:@input_path)).to eq("/path/to/file.xml")
    end

    it "accepts bz2_gem option" do
      processor = described_class.new("/path/to/file.bz2", bz2_gem: true)
      expect(processor.instance_variable_get(:@bz2_gem)).to be true
    end

    it "defaults bz2_gem to false" do
      processor = described_class.new("/path/to/file.bz2")
      expect(processor.instance_variable_get(:@bz2_gem)).to be false
    end
  end
end
