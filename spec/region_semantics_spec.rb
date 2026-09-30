# frozen_string_literal: true

require "spec_helper"
require "wp2txt/lead_terms"
require "wp2txt/link_counter"
require_relative "support/multistream_fixture"

RSpec.describe "literal regions and lead prose" do
  include MultistreamFixture

  def terms(text)
    render = ->(s) { Object.new.extend(Wp2txt).format_wiki(s, expand_templates: true, markers: [:all]) }
    Wp2txt::LeadTerms.extract(text, render: render)
  end

  def counts(text)
    counter = Wp2txt::LinkCounter.new("", [], db_path: "")
    counter.instance_variable_set(:@redirects, {})
    direct, via = Hash.new(0), Hash.new(0)
    counter.send(:count_page, page_xml(id: 1, ns: 0, title: "Source", text: text), direct, via)
    direct
  end

  %w[gallery timeline].each do |tag|
    it "counts links inside #{tag}, but excludes its bold text from the lead" do
      text = "<#{tag}>[[東京]] '''偽'''（にせ）</#{tag}>\n\n'''大阪'''（おおさか）。"
      expect(counts(text)).to eq("東京" => 1)
      expect(terms(text).map { |term| term["text"] }).to eq(["大阪"])
      expect(counts("<#{tag}>[[東京]]<nowiki>[[京都]]</nowiki>[[大阪]]</#{tag}>"))
        .to eq("東京" => 1, "大阪" => 1)
    end
  end

  it "counts links and extracts bold terms inside code as ordinary wikitext" do
    text = "<code>'''東京'''（とうきょう） [[大阪]]</code>"
    expect(counts(text)).to eq("大阪" => 1)
    term = terms(text).first
    expect(term).not_to be_nil
    expect(term.slice("text", "notes")).to eq("text" => "東京", "notes" => ["とうきょう"])
    s, e = term["span"]["bold"]
    expect(text[s...e]).to eq("'''東京'''")
    s, e = term["span"]["paren"]
    expect(text[s...e]).to eq("（とうきょう）")
  end

  %w[nowiki pre math chem ce score syntaxhighlight source graph mapframe templatedata].each do |tag|
    it "excludes literal #{tag} contents from both consumers and protects its pipes" do
      region = "<#{tag}>[[東京]] '''偽'''（にせ）A|B</#{tag}>"
      expect(counts(region + "[[大阪]]")).to eq("大阪" => 1)
      expect(terms(region + "\n\n'''大阪'''（おおさか）。").map { |term| term["text"] }).to eq(["大阪"])
      expect(Wp2txt::WikitextRegions.split_pipes("ruby|#{region}|よみ")).to eq(["ruby", region, "よみ"])
    end
  end

  %w[gallery timeline code].each do |tag|
    it "splits template pipes inside #{tag} while still protecting nested literal regions" do
      expect(Wp2txt::WikitextRegions.split_pipes("ruby|<#{tag}>A|B</#{tag}>|よみ"))
        .to eq(["ruby", "<#{tag}>A", "B</#{tag}>", "よみ"])
      expect(Wp2txt::WikitextRegions.split_pipes("ruby|<#{tag}>A<nowiki>|</nowiki>B|C</#{tag}>|よみ"))
        .to eq(["ruby", "<#{tag}>A<nowiki>|</nowiki>B", "C</#{tag}>", "よみ"])
    end
  end

  it "continues to exclude comments and keeps rule version 2" do
    expect(counts("<!-- [[東京]] -->[[大阪]]")).to eq("大阪" => 1)
    expect(terms("<!-- '''偽''' -->'''大阪'''（おおさか）").first["text"]).to eq("大阪")
    expect(Wp2txt::WikitextRegions.split_pipes("ruby|<!-- a|b -->東京|よみ"))
      .to eq(["ruby", "<!-- a|b -->東京", "よみ"])
    expect(Wp2txt::LinkCounter::RULE_VERSION).to eq("2")
  end
end
