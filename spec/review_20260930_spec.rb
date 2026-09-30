# frozen_string_literal: true

require 'spec_helper'
require 'wp2txt'
require 'wp2txt/lead_terms'
require 'wp2txt/link_counter'
require 'wp2txt/metadata_index'
require 'open3'
require 'tmpdir'
require_relative 'support/multistream_fixture'

RSpec.describe '2026-09-30 review regressions' do
  include MultistreamFixture

  let(:cleaner) { Object.new.extend(Wp2txt) }
  let(:render) { ->(s) { cleaner.format_wiki(s, expand_templates: true, markers: [:all]) } }
  def terms(text)
    Wp2txt::LeadTerms.extract(text, render: render)
  end

  it '#1 preserves link display and reading with expansion enabled or disabled' do
    {
      '{{読み仮名|[[東京|東京都]]|とうきょう}}' => '東京都（とうきょう）',
      '{{仮リンク|[[東京|東京都]]|en|Tokyo}}' => '東京都',
      '{{読み仮名|{{lang|ja|[[東京|東京都]]}}|とうきょう}}' => '東京都（とうきょう）',
      '{{読み仮名|東京|}}' => '東京'
    }.each do |input, expected|
      [true, false].each do |expand|
        expect(cleaner.format_wiki(input, expand_templates: expand)).to eq(expected)
      end
    end
  end

  def build_case_dump(dir, rule)
    alias_title = rule == 'first-letter' ? 'Alias' : 'alias'
    pages = [[1, 'apple', ''], [2, 'Apple', ''], [3, alias_title, '#REDIRECT [[apple]]'],
             [4, 'Direct', '[[apple]]'], [5, 'Via', '[[alias]]'], [6, '東京', '']]
    xml = "<mediawiki><siteinfo><case>#{rule}</case></siteinfo>" + pages.map do |id, title, text|
      page_xml(id: id, ns: 0, title: title, text: text)
    end.join + '</mediawiki>'
    dump = File.join(dir, 'testwiki-20260101-multistream.xml.bz2')
    File.binwrite(dump, bzip2(xml))
    db = File.join(dir, 'meta.sqlite3')
    Wp2txt::MetadataIndexBuilder.new(dump, [0], db_path: db, num_processes: 0).build.close
    [dump, db]
  end

  it '#2 stores siteinfo case and preserves direct and redirected case-sensitive targets' do
    Dir.mktmpdir do |dir|
      dump, path = build_case_dump(dir, 'case-sensitive')
      db = SQLite3::Database.new(path)
      expect(db.get_first_value("SELECT value FROM metadata WHERE key = 'case_rule'")).to eq('case-sensitive')
      db.close
      Wp2txt::LinkCounter.new(dump, [0], db_path: path, num_processes: 0).count!
      db = SQLite3::Database.new(path)
      expect(db.execute('SELECT page_id,inlinks,via_redirects FROM page_inlinks WHERE page_id IN (1,2) ORDER BY page_id'))
        .to eq([[1, 2, 1], [2, 0, 0]])
      db.close
      expect(Wp2txt::MetadataIndex.normalize_title('apple')).to eq('Apple')
    end
  end

  it '#2 uses first-letter for explicit siteinfo and legacy metadata without the rule' do
    Dir.mktmpdir do |dir|
      dump, path = build_case_dump(dir, 'first-letter')
      [false, true].each do |legacy|
        db = SQLite3::Database.new(path)
        if legacy
          db.execute("DELETE FROM metadata WHERE key = 'case_rule'")
        else
          expect(db.get_first_value("SELECT value FROM metadata WHERE key = 'case_rule'")).to eq('first-letter')
        end
        db.close
        Wp2txt::LinkCounter.new(dump, [0], db_path: path, num_processes: 0).count!
        db = SQLite3::Database.new(path)
        expect(db.get_first_value('SELECT inlinks FROM page_inlinks WHERE page_id=1')).to eq(0)
        expect(db.execute('SELECT inlinks,via_redirects FROM page_inlinks WHERE page_id=2')).to eq([[2, 1]])
        db.close
      end
    end
  end

  it '#2 reads a separate siteinfo stream before the first indexed page' do
    Dir.mktmpdir do |dir|
      header = bzip2('<mediawiki><siteinfo><case>case-sensitive</case></siteinfo>')
      dump = File.join(dir, 'dump.xml.bz2')
      File.binwrite(dump, header + bzip2(page_xml(id: 1, ns: 0, title: 'apple', text: '') + '</mediawiki>'))
      path = File.join(dir, 'meta.sqlite3')
      Wp2txt::MetadataIndexBuilder.new(dump, [header.bytesize], db_path: path, num_processes: 0).build.close
      db = SQLite3::Database.new(path)
      expect(db.get_first_value("SELECT value FROM metadata WHERE key = 'case_rule'")).to eq('case-sensitive')
      db.close
    end
  end

  %w[nowiki pre math syntaxhighlight source gallery score timeline chem ce graph mapframe templatedata].each do |tag|
    it "#3 skips #{tag} contents and self-closing forms while preserving source offsets" do
      text = "<#{tag.upcase} data-x='>'>'''偽'''（にせ）{{ruby|偽|にせ}}</#{tag.upcase}>\n\n" \
             "<#{tag} />'''東京'''（とうきょう）。"
      result = terms(text)
      expect(result.map { |t| t['text'] }).to eq(['東京'])
      s, e = result.first['span']['bold']
      expect(text[s...e]).to eq("'''東京'''")
      expect(terms("<#{tag}>'''偽'''" )).to eq([])
    end
  end

  it '#4 ignores delimiters in comments and excluded tags inside parentheses' do
    text = "'''東京'''（とうきょう<!-- ) , -->、<nowiki>),</nowiki>Tokyo）は都市。"
    result = terms(text).first
    s, e = result['span']['paren']
    expect(text[s...e]).to eq('（とうきょう<!-- ) , -->、<nowiki>),</nowiki>Tokyo）')
    expect(result['notes'].size).to eq(2)
    expect(result['notes'].first).to eq('とうきょう')
    expect(result['notes_text']).not_to include('<!--')
  end

  it 'retains the original text of ruby arguments containing excluded regions' do
    expect(terms('{{ruby|<nowiki>東京</nowiki>|とうきょう}}').first.slice('text', 'reading'))
      .to eq('text' => '東京', 'reading' => 'とうきょう')
  end

  it '#5 detects only headings outside skipped regions including trailing comments' do
    ["<!--\n== 偽 ==\n-->", "<nowiki>\n== 偽 ==\n</nowiki>", "{{box|\n== 偽 ==\n}}", "{|\n== 偽 ==\n|}"].each do |prefix|
      expect(terms("#{prefix}\n'''東京'''（とうきょう）").map { |t| t['text'] }).to eq(['東京'])
    end
    expect(terms("導入文。\n\n== 歴史 == <!-- comment -->\n'''後の語'''（あと）。")).to eq([])
  end

  it '#6 allows single newlines before and inside notes but stops at a blank line' do
    expect(terms("'''東京'''\n（とうきょう）は都市。").first['notes']).to eq(['とうきょう'])
    text = "'''東京'''（とうきょう、\nTokyo）は都市。"
    term = terms(text).first
    expect(term['notes']).to eq(['とうきょう', 'Tokyo'])
    s, e = term['span']['paren']
    expect(text[s...e]).to eq("（とうきょう、\nTokyo）")
    ["'''東京'''\n\n（とうきょう）", "'''東京'''（とうきょう、\n \nTokyo）"].each do |input|
      expect(terms(input).first['notes']).to eq([])
    end
  end

  it '#7 stops at empty lines containing whitespace' do
    ["\n \n", "\n\t\n", "\r\n \r\n"].each do |gap|
      expect(terms("'''東京'''（とうきょう）。#{gap}'''別段落'''（べつだんらく）。").map { |t| t['text'] }).to eq(['東京'])
    end
  end

  def counts(text)
    counter = Wp2txt::LinkCounter.new('', [], db_path: '')
    counter.instance_variable_set(:@redirects, {})
    direct, via = Hash.new(0), Hash.new(0)
    counter.send(:count_page, page_xml(id: 1, ns: 0, title: 'Source', text: text), direct, via)
    direct
  end

  it '#8 decodes title entities before sections and normalizes whitespace before colon' do
    expect(counts('[[M&amp;A]] [[Caf&#233;]] [[ :東京#節|表示]] [[Caf&#xE9;#section]] [[#節]] [[]]'))
      .to eq('M&A' => 1, 'Café' => 1, '東京' => 1)
    expect(counts('[[東京&#35;節]] [[東京|表示]]')).to eq('東京' => 1)
  end

  it '#9 excludes every non-wikitext tag and comments from incoming links' do
    %w[nowiki pre math syntaxhighlight source score chem ce graph mapframe templatedata].each do |tag|
      expect(counts("<#{tag}>[[東京]]</#{tag}>[[大阪]]<#{tag}/><!-- [[京都]] -->")).to eq('大阪' => 1)
    end
  end

  it 'handles empty text and binary invalid bytes in the shared region helper' do
    expect(terms('')).to eq([])
    expect(counts('')).to eq({})
    expect(Wp2txt::WikitextRegions.remove_literal("<nowiki>\xFF</nowiki>\xFE".b)).to eq("\xFE".b)
  end

  def cli(*options)
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'x.xml.bz2')
      File.binwrite(input, bzip2("<mediawiki>#{page_xml(id: 1, ns: 0, title: '東京', text: "'''東京'''。")}</mediawiki>"))
      Open3.capture3(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__),
                     File.expand_path('../bin/wp2txt', __dir__), '-i', input, '-o', dir, *options)
    end
  end

  it '#10 rejects lead terms with ractor' do
    _, err, status = cli('--format', 'json', '--lead-terms', '--ractor', '--no-turbo')
    expect(status.success?).to be(false)
    expect(err).to include('--lead-terms cannot be combined with --ractor')
  end

  it '#10 warns about missing source identifiers in ractor JSON without rejecting it' do
    _, err, status = cli('--format', 'json', '--ractor', '--no-turbo', '-n', '1')
    expect(status.success?).to be(true), err
    expect(err).to include('does not include page IDs, revision IDs, or Wikidata QIDs')
  end
end
