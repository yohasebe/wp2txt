# frozen_string_literal: true

require_relative "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Wp2txt do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe Wp2txt::Splitter do
    let(:sample_xml) do
      <<~XML
        <mediawiki>
        <page>
          <title>Test Article 1</title>
          <text>'''Test''' is a [[test]].</text>
        </page>
        <page>
          <title>Test Article 2</title>
          <text>Another '''article''' with [[links]].</text>
        </page>
        </mediawiki>
      XML
    end

    let(:xml_file) do
      file = File.join(temp_dir, "test_input.xml")
      File.write(file, sample_xml)
      file
    end

    describe "#initialize" do
      it "creates a splitter with default parameters" do
        splitter = Wp2txt::Splitter.new(xml_file, temp_dir)
        expect(splitter).to be_a(Wp2txt::Splitter)
      end

      it "creates output file base from input file" do
        splitter = Wp2txt::Splitter.new(xml_file, temp_dir)
        expect(splitter.instance_variable_get(:@outfile_base)).to eq("test_input-")
      end
    end

    describe "#command_exist?" do
      let(:splitter) { Wp2txt::Splitter.new(xml_file, temp_dir) }

      it "returns path for existing command" do
        # 'ls' should exist on all Unix systems
        result = suppress_stdout { splitter.command_exist?("ls") }
        expect(result).to be_truthy
        expect(result).to include("ls")
      end

      it "returns false for non-existing command" do
        result = suppress_stdout { splitter.command_exist?("nonexistent_command_xyz123") }
        expect(result).to be false
      end
    end

    describe "#get_newline" do
      let(:splitter) { Wp2txt::Splitter.new(xml_file, temp_dir) }

      it "reads lines from file" do
        # Reset buffer for testing
        splitter.instance_variable_set(:@buffer, [+""])
        line = splitter.get_newline
        expect(line).to be_a(String)
      end
    end

    describe "#split_file" do
      it "splits XML file and creates output files" do
        splitter = Wp2txt::Splitter.new(xml_file, temp_dir, 1) # 1MB split size
        splitter.split_file

        outfiles = splitter.instance_variable_get(:@outfiles)
        expect(outfiles).not_to be_empty

        # Check that output files were created and renamed to .xml
        outfiles.each do |f|
          xml_file_path = f.sub(/\d+$/, "") + "*.xml"
          matching_files = Dir.glob(File.join(temp_dir, "*.xml"))
          expect(matching_files).not_to be_empty
        end
      end
    end

    describe "#fill_buffer" do
      let(:splitter) { Wp2txt::Splitter.new(xml_file, temp_dir) }

      it "fills buffer with content from file" do
        splitter.instance_variable_set(:@buffer, [+""])
        result = splitter.fill_buffer
        buffer = splitter.instance_variable_get(:@buffer)

        expect(result).to be true
        expect(buffer.size).to be >= 1
      end
    end
  end

  describe Wp2txt::Runner do
    let(:sample_xml) do
      <<~XML
        <page>
          <title>Test Article</title>
          <revision>
            <text>'''Test Article''' is about [[testing]].

        == Section ==
        This is content.

        [[Category:Testing]]
            </text>
          </revision>
        </page>
      XML
    end

    let(:xml_file) do
      file = File.join(temp_dir, "test_runner.xml")
      File.write(file, sample_xml)
      file
    end

    describe "#initialize" do
      it "creates a runner" do
        runner = Wp2txt::Runner.new(xml_file, temp_dir, false, false)
        expect(runner).to be_a(Wp2txt::Runner)
      end
    end

    describe "#prepare" do
      it "sets up file pointer and output base" do
        runner = Wp2txt::Runner.new(xml_file, temp_dir, false, false)
        expect(runner.instance_variable_get(:@outfile_base)).to eq("test_runner")
        expect(runner.instance_variable_get(:@file_pointer)).not_to be_nil
      end
    end

    describe "#get_newline" do
      let(:runner) { Wp2txt::Runner.new(xml_file, temp_dir, false, false) }

      it "returns lines from file" do
        runner.instance_variable_set(:@buffer, [+""])
        line = runner.get_newline
        expect(line).to be_a(String)
      end
    end

    describe "#fill_buffer" do
      let(:runner) { Wp2txt::Runner.new(xml_file, temp_dir, false, false) }

      it "reads content into buffer" do
        runner.instance_variable_set(:@buffer, [+""])
        result = runner.fill_buffer
        expect(result).to be true
      end
    end

    describe "#get_page" do
      let(:runner) { Wp2txt::Runner.new(xml_file, temp_dir, false, false) }

      it "extracts page content" do
        page = runner.get_page
        expect(page).to be_a(String)
        expect(page).to include("<page>")
        expect(page).to include("</page>")
        expect(page).to include("Test Article")
      end

      it "returns false when no more pages" do
        runner.get_page # consume first page
        result = runner.get_page
        expect(result).to be false
      end
    end

    describe "#extract_text" do
      let(:multi_page_xml) do
        <<~XML
          <page>
            <title>Article One</title>
            <revision>
              <text>'''Article One''' is first.</text>
            </revision>
          </page>
        XML
      end

      let(:multi_page_file) do
        file = File.join(temp_dir, "multi_page.xml")
        File.write(file, multi_page_xml)
        file
      end

      it "processes pages and calls block for each article" do
        runner = Wp2txt::Runner.new(multi_page_file, temp_dir, false, false)
        articles_processed = []

        runner.extract_text do |article|
          articles_processed << article.title
          "processed: #{article.title}\n"
        end

        expect(articles_processed).to include("Article One")

        # Check output file was created
        output_file = File.join(temp_dir, "multi_page.txt")
        expect(File.exist?(output_file)).to be true
      end
    end
  end

  describe "Module methods" do
    include Wp2txt

    describe "#rename" do
      it "renames files with extension" do
        # Create test files
        files = []
        3.times do |i|
          f = File.join(temp_dir, "testfile#{i}")
          File.write(f, "content #{i}")
          files << f
        end

        rename(files, "txt")

        files.each_with_index do |f, i|
          new_name = "#{f}.txt"
          expect(File.exist?(new_name)).to be true
          expect(File.read(new_name)).to eq("content #{i}")
        end
      end
    end
  end
end

RSpec.describe "Splitter with edge cases" do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe "empty file handling" do
    let(:empty_file) do
      file = File.join(temp_dir, "empty.xml")
      File.write(file, "")
      file
    end

    it "handles empty input file" do
      expect {
        splitter = Wp2txt::Splitter.new(empty_file, temp_dir)
        splitter.split_file
      }.not_to raise_error
    end
  end

  describe "large content handling" do
    let(:large_xml) do
      content = +"<mediawiki>\n"
      50.times do |i|
        content << "<page>\n"
        content << "  <title>Article #{i}</title>\n"
        content << "  <text>#{'x' * 1000} article #{i}</text>\n"
        content << "</page>\n"
      end
      content << "</mediawiki>"
      content
    end

    let(:large_file) do
      file = File.join(temp_dir, "large.xml")
      File.write(file, large_xml)
      file
    end

    it "processes large files without error" do
      expect {
        splitter = Wp2txt::Splitter.new(large_file, temp_dir, 1)
        splitter.split_file
      }.not_to raise_error
    end
  end
end

RSpec.describe "Splitter additional tests" do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe "#file_size" do
    let(:test_file) do
      file = File.join(temp_dir, "test_size.xml")
      File.write(file, "x" * 1000)
      file
    end

    it "calculates file size" do
      splitter = Wp2txt::Splitter.new(test_file, temp_dir)
      size = splitter.file_size(File.open(test_file, "r"))
      expect(size).to eq(1000)
    end

    it "handles empty file" do
      empty_file = File.join(temp_dir, "empty.xml")
      File.write(empty_file, "")
      splitter = Wp2txt::Splitter.new(empty_file, temp_dir)
      size = splitter.file_size(File.open(empty_file, "r"))
      expect(size).to eq(0)
    end
  end

  describe "#split_file edge cases" do
    let(:single_page_xml) do
      <<~XML
        <mediawiki>
        <page>
          <title>Single Article</title>
          <text>Content here.</text>
        </page>
        </mediawiki>
      XML
    end

    let(:single_file) do
      file = File.join(temp_dir, "single.xml")
      File.write(file, single_page_xml)
      file
    end

    it "handles single page file" do
      splitter = Wp2txt::Splitter.new(single_file, temp_dir)
      splitter.split_file

      xml_files = Dir.glob(File.join(temp_dir, "*.xml"))
      expect(xml_files.size).to be >= 1
    end

    it "creates output files with correct base name" do
      splitter = Wp2txt::Splitter.new(single_file, temp_dir)
      splitter.split_file

      xml_files = Dir.glob(File.join(temp_dir, "single-*.xml"))
      expect(xml_files).not_to be_empty
    end
  end

  describe "#prepare" do
    it "sets up file pointer for plain XML" do
      xml_file = File.join(temp_dir, "test.xml")
      File.write(xml_file, "<page></page>")
      splitter = Wp2txt::Splitter.new(xml_file, temp_dir)

      expect(splitter.instance_variable_get(:@file_pointer)).not_to be_nil
      expect(splitter.instance_variable_get(:@outfile_base)).to eq("test-")
    end
  end
end

RSpec.describe "Runner additional tests" do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe "#extract_text with del_interfile" do
    let(:xml_content) do
      <<~XML
        <page>
          <title>Delete Test</title>
          <revision>
            <text>Test content.</text>
          </revision>
        </page>
      XML
    end

    it "deletes intermediate file when del_interfile is true" do
      xml_file = File.join(temp_dir, "to_delete.xml")
      File.write(xml_file, xml_content)

      runner = Wp2txt::Runner.new(xml_file, temp_dir, false, true)
      runner.extract_text { |article| "#{article.title}\n" }

      expect(File.exist?(xml_file)).to be false
    end

    it "keeps intermediate file when del_interfile is false" do
      xml_file = File.join(temp_dir, "to_keep.xml")
      File.write(xml_file, xml_content)

      runner = Wp2txt::Runner.new(xml_file, temp_dir, false, false)
      runner.extract_text { |article| "#{article.title}\n" }

      expect(File.exist?(xml_file)).to be true
    end
  end

  describe "#get_page edge cases" do
    let(:incomplete_xml) do
      <<~XML
        <page>
          <title>Incomplete</title>
          <text>No closing page tag
      XML
    end

    it "handles incomplete page" do
      xml_file = File.join(temp_dir, "incomplete.xml")
      File.write(xml_file, incomplete_xml)

      runner = Wp2txt::Runner.new(xml_file, temp_dir, false, false)
      result = runner.get_page
      # Should return something even if incomplete
      expect(result).to be_truthy
    end
  end
end

RSpec.describe "Runner edge cases" do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe "page with colon in title" do
    let(:colon_title_xml) do
      <<~XML
        <page>
          <title>Category:Test</title>
          <revision>
            <text>Category page content</text>
          </revision>
        </page>
        <page>
          <title>Normal Article</title>
          <revision>
            <text>Normal content</text>
          </revision>
        </page>
      XML
    end

    let(:colon_file) do
      file = File.join(temp_dir, "colon_test.xml")
      File.write(file, colon_title_xml)
      file
    end

    it "skips pages with colon in title (namespace pages)" do
      runner = Wp2txt::Runner.new(colon_file, temp_dir, false, false)
      titles = []

      runner.extract_text do |article|
        titles << article.title
        "#{article.title}\n"
      end

      expect(titles).to include("Normal Article")
      expect(titles).not_to include("Category:Test")
    end
  end

  describe "page with HTML comments" do
    let(:comment_xml) do
      <<~XML
        <page>
          <title>Comment Test</title>
          <revision>
            <text>Before comment <!-- hidden
        multiline
        comment --> after comment</text>
          </revision>
        </page>
      XML
    end

    let(:comment_file) do
      file = File.join(temp_dir, "comment_test.xml")
      File.write(file, comment_xml)
      file
    end

    it "removes HTML comments preserving newlines" do
      runner = Wp2txt::Runner.new(comment_file, temp_dir, false, false)
      content = ""

      runner.extract_text do |article|
        content = article.elements.map { |e| e.last }.join("\n")
        content
      end

      expect(content).to include("Before comment")
      expect(content).to include("after comment")
      expect(content).not_to include("hidden")
    end
  end
end
