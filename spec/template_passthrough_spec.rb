# frozen_string_literal: true

require "spec_helper"
require "wp2txt"
require "wp2txt/formatter"

# Templates the cleaning stage renders itself must survive template expansion;
# deleting them earlier silently dropped readings and link text from articles.
RSpec.describe "templates rendered by the cleaning stage" do
  include Wp2txt
  include Wp2txt::Formatter

  def summary_of(wikitext)
    article = Wp2txt::Article.new("#{wikitext}\n\n== 節 ==\n本文\n", "T", true)
    format_article(article, { format: :json, summary_only: true, expand_templates: true,
                              markers: [:all] })["text"].strip
  end

  {
    "'''{{読み仮名|言語|げんご}}'''は記号体系。" => "言語（げんご）は記号体系。",
    "{{読み仮名_ruby不使用|東京|とうきょう}}都" => "東京（とうきょう）都",
    "作曲は{{仮リンク|ジョン・ドウ|en|John Doe}}が担当した。" => "作曲はジョン・ドウが担当した。",
    "{{ruby|漢字|かんじ}}を読む。" => "漢字（かんじ）を読む。",
    "作曲は{{仮リンク|{{lang|en|John Doe}}|en|John Doe}}。" => "作曲はJohn Doe。"
  }.each do |source, expected|
    it "renders #{source.inspect}" do
      expect(summary_of(source)).to eq(expected)
    end
  end

  it "keeps an image caption that contains a link template" do
    source = "[[ファイル:Stele.jpg|thumb|200px|[[ナラム・シン]]。画像は{{仮リンク|戦勝記念碑|en|Victory Stele}}。]]\n'''紀元前23世紀'''は世紀。"
    expect(summary_of(source)).to include("ナラム・シン。画像は戦勝記念碑。")
  end

  it "still removes templates nothing downstream knows" do
    expect(summary_of("前{{Otheruses|x|y}}後")).to eq("前後")
  end

  it "adds no empty brackets for an empty reading" do
    expect(summary_of("{{読み仮名|語|}}は")).to eq("語は")
  end
end
