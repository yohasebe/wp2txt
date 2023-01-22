# frozen_string_literal: true

require "htmlentities"

module Wp2txt
  ###################################################
  # variables to save resource for generating regexps
  # those with a trailing number 1 represent opening tag/markup
  # those with a trailing number 2 represent closing tag/markup
  # those without a trailing number contain both opening/closing tags/markups

  HTML_DECODER = HTMLEntities.new

  ENTITIES = ['&nbsp;', '&lt;', '&gt;', '&amp;', '&quot;'].zip([' ', '<', '>', '&', '"'])
  HTML_HASH = Hash[*ENTITIES.flatten]
  HTML_REGEX = Regexp.new("(" + HTML_HASH.keys.join("|") + ")")
  ML_TEMPLATE_ONSET_REGEX = Regexp.new('^\{\{[^\}]*$')
  ML_TEMPLATE_END_REGEX = Regexp.new('\}\}\s*$')
  ML_LINK_ONSET_REGEX = Regexp.new('^\[\[[^\]]*$')
  ML_LINK_END_REGEX = Regexp.new('\]\]\s*$')
  ISOLATED_TEMPLATE_REGEX = Regexp.new('^\s*\{\{.+\}\}\s*$')
  ISOLATED_TAG_REGEX = Regexp.new('^\s*\<[^\<\>]+\>.+\<[^\<\>]+\>\s*$')
  IN_LINK_REGEX = Regexp.new('^\s*\[.*\]\s*$')
  IN_INPUTBOX_REGEX = Regexp.new('<inputbox>.*?<\/inputbox>')
  IN_INPUTBOX_REGEX1 = Regexp.new('<inputbox>')
  IN_INPUTBOX_REGEX2 = Regexp.new('<\/inputbox>')
  IN_SOURCE_REGEX = Regexp.new('<source.*?>.*?<\/source>')
  IN_SOURCE_REGEX1 = Regexp.new('<source.*?>')
  IN_SOURCE_REGEX2 = Regexp.new('<\/source>')
  IN_MATH_REGEX = Regexp.new('<math.*?>.*?<\/math>')
  IN_MATH_REGEX1 = Regexp.new('<math.*?>')
  IN_MATH_REGEX2 = Regexp.new('<\/math>')
  IN_HEADING_REGEX = Regexp.new('^=+.*?=+$')
  IN_HTML_TABLE_REGEX = Regexp.new("<table.*?><\/table>")
  IN_HTML_TABLE_REGEX1 = Regexp.new('<table\b')
  IN_HTML_TABLE_REGEX2 = Regexp.new('<\/\s*table>')
  IN_TABLE_REGEX1 = Regexp.new('^\s*\{\|')
  IN_TABLE_REGEX2 = Regexp.new('^\|\}.*?$')
  IN_UNORDERED_REGEX = Regexp.new('^\*')
  IN_ORDERED_REGEX = Regexp.new('^\#')
  IN_PRE_REGEX = Regexp.new('^ ')
  IN_DEFINITION_REGEX = Regexp.new('^[\;\:]')
  BLANK_LINE_REGEX = Regexp.new('^\s*$')
  REDIRECT_REGEX = Regexp.new('#(?:REDIRECT|転送)\s+\[\[(.+)\]\]', Regexp::IGNORECASE)
  REMOVE_TAG_REGEX = Regexp.new("\<[^\<\>]*\>")
  REMOVE_DIRECTIVES_REGEX = Regexp.new("\_\_[^\_]*\_\_")
  REMOVE_EMPHASIS_REGEX = Regexp.new('(' + Regexp.escape("''") + '+)(.+?)\1')
  CHRREF_TO_UTF_REGEX = Regexp.new('&#(x?)([0-9a-fA-F]+);')
  MNDASH_REGEX = Regexp.new('\{(mdash|ndash|–)\}')
  REMOVE_HR_REGEX = Regexp.new('^\s*\-+\s*$')
  MAKE_REFERENCE_REGEX_A = Regexp.new('<br ?\/>')
  MAKE_REFERENCE_REGEX_B = Regexp.new('<ref[^>]*\/>')
  MAKE_REFERENCE_REGEX_C = Regexp.new('<ref[^>]*>')
  MAKE_REFERENCE_REGEX_D = Regexp.new('<\/ref>')
  FORMAT_REF_REGEX = Regexp.new('\[ref\](.*?)\[\/ref\]', Regexp::MULTILINE)
  HEADING_ONSET_REGEX = Regexp.new('^(\=+)\s+')
  HEADING_CODA_REGEX = Regexp.new('\s+(\=+)$')
  LIST_MARKS_REGEX = Regexp.new('\A[\*\#\;\:\ ]+')
  PRE_MARKS_REGEX = Regexp.new('\A\^\ ')
  DEF_MARKS_REGEX = Regexp.new('\A[\;\:\ ]+')
  ONSET_BAR_REGEX = Regexp.new('\A[^\|]+\z')

  CATEGORY_PATTERNS = ["Category", "Categoria"].join("|")
  CATEGORY_REGEX = Regexp.new('[\{\[\|\b](?:' + CATEGORY_PATTERNS + ')\:(.*?)[\}\]\|\b]', Regexp::IGNORECASE)

  ESCAPE_NOWIKI_REGEX = Regexp.new('<nowiki>(.*?)<\/nowiki>', Regexp::MULTILINE)
  UNESCAPE_NOWIKI_REGEX = Regexp.new('<nowiki\-(\d+?)>')

  REMOVE_ISOLATED_REGEX = Regexp.new('^\s*\{\{(.*?)\}\}\s*$')
  REMOVE_INLINE_REGEX = Regexp.new('\{\{(.*?)\}\}')
  TYPE_CODE_REGEX = Regexp.new('\A(?:lang*|\AIPA|IEP|SEP|indent|audio|small|dmoz|pron|unicode|note label|nowrap|ArabDIN|trans|Nihongo|Polytonic)', Regexp::IGNORECASE)

  SINGLE_SQUARE_BRACKET_REGEX = Regexp.new("(#{Regexp.escape("[")}|#{Regexp.escape("]")})", Regexp::MULTILINE)
  DOUBLE_SQUARE_BRACKET_REGEX = Regexp.new("(#{Regexp.escape("[[")}|#{Regexp.escape("]]")})", Regexp::MULTILINE)
  SINGLE_CURLY_BRACKET_REGEX = Regexp.new("(#{Regexp.escape("{")}|#{Regexp.escape("}")})", Regexp::MULTILINE)
  DOUBLE_CURLY_BRACKET_REGEX = Regexp.new("(#{Regexp.escape("{{")}|#{Regexp.escape("}}")})", Regexp::MULTILINE)
  CURLY_SQUARE_BRACKET_REGEX = Regexp.new("(#{Regexp.escape("{|")}|#{Regexp.escape("|}")})", Regexp::MULTILINE)

  COMPLEX_REGEX_01 = Regexp.new('\<\<([^<>]++)\>\>\s?')
  COMPLEX_REGEX_02 = Regexp.new('\[\[File\:((?:[^\[\]]++|\[\[\g<1>\]\])++)\]\]', Regexp::MULTILINE | Regexp::IGNORECASE)
  COMPLEX_REGEX_03 = Regexp.new('^\[\[((?:[^\[\]]++|\[\[\g<1>\]\])++)^\]\]', Regexp::MULTILINE)
  COMPLEX_REGEX_04 = Regexp.new('\{\{(?:infobox|efn|sfn|unreliable source|refn|reflist|col(?:umns)?\-list|div col|no col|bar box|formatnum\:|col\||see also\||r\||#)((?:[^{}]++|\{\{\g<1>\}\})++)\}\}', Regexp::MULTILINE | Regexp::IGNORECASE)
  COMPLEX_REGEX_05 = Regexp.new('\{\{[^{}]+?\n\|((?:[^{}]++|\{\{\g<1>\}\})++)\}\}', Regexp::MULTILINE | Regexp::IGNORECASE)

  CLEANUP_REGEX_01 = Regexp.new('\[ref\]\s*\[\/ref\]', Regexp::MULTILINE)
  CLEANUP_REGEX_02 = Regexp.new('^File:.+$')
  CLEANUP_REGEX_03 = Regexp.new('^\|.*$')
  CLEANUP_REGEX_04 = Regexp.new('\{\{.*$')
  CLEANUP_REGEX_05 = Regexp.new('^.*\}\}')
  CLEANUP_REGEX_06 = Regexp.new('\{\|.*$')
  CLEANUP_REGEX_07 = Regexp.new('^.*\|\}')
  CLEANUP_REGEX_08 = Regexp.new('\n\n\n+', Regexp::MULTILINE)
end
