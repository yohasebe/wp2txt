#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'wp2txt'
require 'wp2txt/article'
require 'wp2txt/utils'

$limit_recur = 3

describe "Wp2txt" do
  it "contains mediawiki-format related functions:" do
  end

  include Wp2txt

  before do
  end

  describe "process_nested_structure" do
    it "parse nested structure replacing str in the format specified" do
      str_before = "[[ab[[cde[[alfa]]]]fg]]"
      str_after  = "<<ab<<cde<<alfa>>>>fg>>"
      scanner = StringScanner.new(str_before)
      str_processed = process_nested_structure(scanner, "[[", "]]", $limit_recur) do |content|
        "<<" + content + ">>"
      end
      expect(str_processed).to eq str_after
      
      str_before = "#* {{quote-book|1503|year_published=1836|chapter=19 Henry VII. c. 5: Coin||A Collection of Statutes Connected with the General Administration of the Law|page=158|url=http://books.google.com/books?id=QtYuAAAAIAAJ
      |passage={{...}} every of them, being gold, whole and weight, shall '''go''' and be current in payment throughout this his realm for the sum that they were coined for.}}"
      str_after = "#* <<quote-book|1503|year_published=1836|chapter=19 Henry VII. c. 5: Coin||A Collection of Statutes Connected with the General Administration of the Law|page=158|url=http://books.google.com/books?id=QtYuAAAAIAAJ
      |passage=<<...>> every of them, being gold, whole and weight, shall '''go''' and be current in payment throughout this his realm for the sum that they were coined for.>>"
      scanner = StringScanner.new(str_before)
      str_processed = process_nested_structure(scanner, "{{", "}}", $limit_recur) do |content|
        "<<" + content + ">>"
      end
      #str_processed.should == str_after
      expect(str_processed).to eq str_after
      
    end
  end
  
  describe "special_chr!" do
    it "replaces character references with real characters" do
      str_before = "&nbsp; &lt; &gt; &amp; &quot;"
      str_after  = "  < > & \""
      special_chr!(str_before)
      expect(str_before).to eq str_after
    end    
  end
  
  describe "chrref_to_utf!" do
    it "replaces character references with real characters" do
      str_before = "&#x266A;"
      str_after  = "♪"
      chrref_to_utf!(str_before)
      expect(str_before).to eq str_after
    end
  end
  
  describe "mndash!" do
    it "replaces {mdash}, {ndash}, or {–} with '–'" do
      str_before = "{mdash} {ndash} {–}"
      str_after  = "– – –"
      mndash!(str_before)
      expect(str_before).to eq str_after
    end
  end
  
  describe "make_reference" do
    it "replaces <ref> tag with [ref]" do
      str_before = "<ref> ... </ref>"
      str_after  = "[ref] ... [/ref]"
      make_reference!(str_before)
      expect(str_before).to eq str_after
    end    
  end
  
  describe "remove_table!" do
    it "removes table formated parts" do
      str_before = "{| ... \n{| ... \n ...|}\n ...|}"
      str_after  = ""
      remove_table!(str_before)
      expect(str_before).to eq str_after
    end    
  end

  # describe "remove_clade" do
  #   it "removes clade formated parts" do
  #     str_before = "\{\{clade ... \n ... \n ... \n\}\}"
  #     str_after  = ""
  #     expect(remove_clade(str_before)).to eq str_after
  #   end
  # end
  
  describe "remove_hr!" do
    it "removes horizontal lines" do
      str_before = "\n----\n--\n--\n"
      str_after  = "\n\n"
      remove_hr!(str_before)
      expect(str_before).to eq str_after
    end    
  end

  describe "remove_inbetween!" do
    it "removes tags and its contents" do
      str_before = "<tag>abc</tag>"
      str_after  = "abc"
      remove_tag!(str_before)
      expect(str_before).to eq str_after
      str_before = "[tag]def[/tag]"
      str_after  = "def"
      remove_inbetween!(str_before, ['[', ']'])
      expect(str_before).to eq str_after
    end    
  end
  
  describe "remove_directive!" do
    it "removes directive" do
      str_before = "__abc__\n __def__"
      str_after  = "\n "
      remove_directive!(str_before)
      expect(str_before).to eq str_after
    end    
  end

  describe "remove_emphasis!" do
    it "removes directive" do
      str_before = "''abc''\n'''def'''"
      str_after  = "abc\ndef"
      remove_emphasis!(str_before)
      expect(str_before).to eq str_after
    end    
  end
  
  describe "escape_nowiki!" do
    it "replaces <nowiki>...</nowiki> with <nowiki-object_id>" do
      str_before = "<nowiki>[[abc]]</nowiki>def<nowiki>[[ghi]]</nowiki>"
      str_after  = Regexp.new("<nowiki-\\d+>def<nowiki-\\d+>")
      escape_nowiki!(str_before)
      expect(str_before).to match str_after
    end
  end

  describe "unescape_nowiki!" do
    it "replaces <nowiki-object_id> with string stored elsewhere" do
      @nowikis = {123 => "[[abc]]", 124 => "[[ghi]]"}
      str_before = "<nowiki-123>def<nowiki-124>"
      str_after  = "[[abc]]def[[ghi]]"
      unescape_nowiki!(str_before)
      expect(str_before).to eq str_after
    end
  end
  
  describe "process_interwiki_links!" do
    it "formats text link and remove brackets" do
      a = "[[a b]]"
      b = "[[a b|c]]"
      c = "[[a|b|c]]"
      d = "[[硬口蓋鼻音|[ɲ], /J/]]"
      process_interwiki_links!(a)
      process_interwiki_links!(b)
      process_interwiki_links!(c)
      process_interwiki_links!(d)
      expect(a).to eq "a b"
      expect(b).to eq "c"
      expect(c).to eq "b|c"
      expect(d).to eq "[ɲ], /J/"
    end
  end

  describe "process_external_links!" do
    it "formats text link and remove brackets" do
      a = "[http://yohasebe.com yohasebe.com]"
      b = "[http://yohasebe.com]"
      c = "* Turkish: {{t+|tr|köken bilimi}}]], {{t+|tr|etimoloji}}"
      process_external_links!(a)
      process_external_links!(b)
      process_external_links!(c)
      expect(a).to eq "yohasebe.com"      
      expect(b).to eq "http://yohasebe.com"
      expect(c).to eq "* Turkish: {{t+|tr|köken bilimi}}]], {{t+|tr|etimoloji}}"
    end
  end
  
  # describe "process_template" do
  #   it "removes brackets and leaving some text" do
  #     str_before = "{{}}"
  #     str_after = ""
  #     expect(process_template(str_before)).to eq str_after
  #     str_before = "{{lang|en|Japan}}"
  #     str_after  = "Japan"
  #     expect(process_template(str_before)).to eq str_after
  #     str_before = "{{a|b=c|d=f}}"
  #     str_after  = "a"
  #     expect(process_template(str_before)).to eq str_after
  #     str_before = "{{a|b|{{c|d|e}}}}"
  #     str_after  = "e"
  #     expect(process_template(str_before)).to eq str_after
  #   end
  # end
  
  #   describe "expand_template" do
  #     it "gets data corresponding to a given template using mediawiki api" do
  #       uri = "http://en.wiktionary.org/w/api.php"
  #       template = "{{en-verb}}"
  #       word = "kick"
  #       expanded = expand_template(uri, template, word)
  #       html =<<EOD
  # <span class=\"infl-inline\"><b class=\"Latn \" lang=\"en\">kick</b> (''third-person singular simple present'' <span class=\"form-of third-person-singular-form-of\">'''<span class=\"Latn \" lang=\"en\">[[kicks#English|kicks]]</span>'''</span>, ''present participle'' <span class=\"form-of present-participle-form-of\">'''<span class=\"Latn \" lang=\"en\">[[kicking#English|kicking]]</span>'''</span>, ''simple past and past participle'' <span class=\"form-of simple-past-and-participle-form-of\"> '''<span class=\"Latn \" lang=\"en\">[[kicked#English|kicked]]</span>'''</span>)</span>[[Category:English verbs|kick]]
  # EOD
  #       html.strip!
  #       expanded.should == html
  #     end
  #   end
end