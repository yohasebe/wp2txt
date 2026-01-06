# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Wp2txt Regex Patterns" do
  # Define local references to module constants
  let(:remove_hr_regex) { Wp2txt::REMOVE_HR_REGEX }
  let(:in_heading_regex) { Wp2txt::IN_HEADING_REGEX }
  let(:redirect_regex) { Wp2txt::REDIRECT_REGEX }
  let(:category_regex) { Wp2txt::CATEGORY_REGEX }
  let(:in_link_regex) { Wp2txt::IN_LINK_REGEX }
  let(:ml_template_onset_regex) { Wp2txt::ML_TEMPLATE_ONSET_REGEX }
  let(:ml_template_end_regex) { Wp2txt::ML_TEMPLATE_END_REGEX }
  let(:blank_line_regex) { Wp2txt::BLANK_LINE_REGEX }
  let(:isolated_template_regex) { Wp2txt::ISOLATED_TEMPLATE_REGEX }
  let(:chrref_to_utf_regex) { Wp2txt::CHRREF_TO_UTF_REGEX }
  let(:in_table_regex1) { Wp2txt::IN_TABLE_REGEX1 }
  let(:in_table_regex2) { Wp2txt::IN_TABLE_REGEX2 }
  let(:in_unordered_regex) { Wp2txt::IN_UNORDERED_REGEX }
  let(:in_ordered_regex) { Wp2txt::IN_ORDERED_REGEX }
  let(:in_definition_regex) { Wp2txt::IN_DEFINITION_REGEX }

  describe "REMOVE_HR_REGEX" do
    it "matches horizontal rules with 4+ hyphens" do
      expect("----").to match(remove_hr_regex)
      expect("----------").to match(remove_hr_regex)
      expect("  ----  ").to match(remove_hr_regex)
    end

    it "does NOT match fewer than 4 hyphens" do
      # These tests will FAIL with current implementation (exposing the bug)
      expect("-").not_to match(remove_hr_regex)
      expect("--").not_to match(remove_hr_regex)
      expect("---").not_to match(remove_hr_regex)
    end
  end

  describe "IN_HEADING_REGEX" do
    it "matches valid headings with equal = counts" do
      expect("== Title ==").to match(in_heading_regex)
      expect("=== Section ===").to match(in_heading_regex)
      expect("==== Subsection ====").to match(in_heading_regex)
    end

    # These tests document the expected behavior after fix
    # Current implementation may not enforce matching = counts
    it "handles headings with trailing whitespace" do
      expect("== Title ==  ").to match(in_heading_regex)
    end
  end

  describe "REDIRECT_REGEX" do
    it "captures English redirect target correctly" do
      match = "#REDIRECT [[Target Page]]".match(redirect_regex)
      expect(match).not_to be_nil
      expect(match[1]).to eq "Target Page"
    end

    it "handles Japanese redirect" do
      match = "#転送 [[日本語ページ]]".match(redirect_regex)
      expect(match).not_to be_nil
      expect(match[1]).to eq "日本語ページ"
    end

    it "is case-insensitive for REDIRECT" do
      match = "#redirect [[Page]]".match(redirect_regex)
      expect(match).not_to be_nil
    end

    it "handles German redirect" do
      match = "#WEITERLEITUNG [[Zielseite]]".match(redirect_regex)
      expect(match).not_to be_nil
      expect(match[1]).to eq "Zielseite"
    end

    it "handles French redirect" do
      match = "#REDIRECTION [[Page cible]]".match(redirect_regex)
      expect(match).not_to be_nil
      expect(match[1]).to eq "Page cible"
    end

    it "handles Russian redirect" do
      match = "#ПЕРЕНАПРАВЛЕНИЕ [[Целевая страница]]".match(redirect_regex)
      expect(match).not_to be_nil
      expect(match[1]).to eq "Целевая страница"
    end

    it "handles Chinese redirect" do
      match = "#重定向 [[目标页面]]".match(redirect_regex)
      expect(match).not_to be_nil
      expect(match[1]).to eq "目标页面"
    end

    it "handles Korean redirect" do
      match = "#넘겨주기 [[대상 문서]]".match(redirect_regex)
      expect(match).not_to be_nil
      expect(match[1]).to eq "대상 문서"
    end
  end

  describe "CATEGORY_REGEX" do
    it "matches English categories" do
      expect("[[Category:Science]]").to match(category_regex)
    end

    it "matches Italian/Spanish categories" do
      expect("[[Categoria:Scienza]]").to match(category_regex)
    end

    it "matches Japanese categories" do
      expect("[[カテゴリ:科学]]").to match(category_regex)
    end

    it "matches German categories" do
      expect("[[Kategorie:Wissenschaft]]").to match(category_regex)
    end

    it "matches French categories" do
      expect("[[Catégorie:Science]]").to match(category_regex)
    end

    it "matches Chinese categories" do
      expect("[[分类:科学]]").to match(category_regex)
      expect("[[分類:科學]]").to match(category_regex)
    end

    it "matches Russian categories" do
      expect("[[Категория:Наука]]").to match(category_regex)
    end

    it "matches Korean categories" do
      expect("[[분류:과학]]").to match(category_regex)
    end

    it "matches Arabic categories" do
      expect("[[تصنيف:علم]]").to match(category_regex)
    end
  end

  describe "IN_LINK_REGEX" do
    it "matches wikilinks on their own line" do
      expect("[[Article]]").to match(in_link_regex)
    end

    it "matches wikilinks with leading/trailing whitespace" do
      expect("  [[Page|Text]]  ").to match(in_link_regex)
    end
  end

  describe "ML_TEMPLATE_ONSET_REGEX" do
    it "matches opening of multi-line templates" do
      expect("{{Infobox").to match(ml_template_onset_regex)
      expect("{{Template name").to match(ml_template_onset_regex)
    end

    it "does not match complete templates" do
      expect("{{Complete}}").not_to match(ml_template_onset_regex)
    end
  end

  describe "ML_TEMPLATE_END_REGEX" do
    it "matches closing of multi-line templates" do
      expect("}}").to match(ml_template_end_regex)
      expect("}}  ").to match(ml_template_end_regex)
      expect("content}}").to match(ml_template_end_regex)
    end
  end

  describe "BLANK_LINE_REGEX" do
    it "matches empty lines" do
      expect("").to match(blank_line_regex)
      expect("   ").to match(blank_line_regex)
      expect("\t").to match(blank_line_regex)
    end

    it "does not match lines with content" do
      expect("text").not_to match(blank_line_regex)
    end
  end

  describe "ISOLATED_TEMPLATE_REGEX" do
    it "matches single-line templates" do
      expect("{{Template}}").to match(isolated_template_regex)
      expect("  {{Template|param}}  ").to match(isolated_template_regex)
    end
  end

  describe "CHRREF_TO_UTF_REGEX" do
    it "matches decimal character references" do
      expect("&#65;").to match(chrref_to_utf_regex)
      expect("&#9834;").to match(chrref_to_utf_regex)
    end

    it "matches hexadecimal character references" do
      expect("&#x41;").to match(chrref_to_utf_regex)
      expect("&#x266A;").to match(chrref_to_utf_regex)
      expect("&#x1F600;").to match(chrref_to_utf_regex)
    end
  end

  describe "IN_TABLE_REGEX1 and IN_TABLE_REGEX2" do
    it "matches MediaWiki table start" do
      expect("{|").to match(in_table_regex1)
      expect("  {|").to match(in_table_regex1)
    end

    it "matches MediaWiki table end" do
      expect("|}").to match(in_table_regex2)
    end
  end

  describe "List detection regexes" do
    it "detects unordered list items" do
      expect("* Item").to match(in_unordered_regex)
      expect("** Nested").to match(in_unordered_regex)
    end

    it "detects ordered list items" do
      expect("# Item").to match(in_ordered_regex)
      expect("## Nested").to match(in_ordered_regex)
    end

    it "detects definition list items" do
      expect("; Term").to match(in_definition_regex)
      expect(": Definition").to match(in_definition_regex)
    end
  end
end
