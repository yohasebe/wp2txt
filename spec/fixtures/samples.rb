# frozen_string_literal: true

# Test samples for multilingual content
module Wp2txt
  module TestSamples
    ENGLISH_ARTICLE = <<~WIKI
      '''Test Article''' is an [[English language|English]] article.
      == Section ==
      [[File:Example.jpg|thumb|A description]]
      [[Category:Tests]]
      [[Category:Examples]]
    WIKI

    JAPANESE_ARTICLE = <<~WIKI
      '''テスト記事'''は[[日本語]]の記事です。
      == セクション ==
      [[ファイル:Example.jpg|thumb|説明文]]
      [[カテゴリ:テスト]]
    WIKI

    GERMAN_ARTICLE = <<~WIKI
      '''Testartikel''' ist ein [[Deutsch|deutscher]] Artikel.
      == Abschnitt ==
      [[Datei:Bild.png|miniatur|Beschreibung]]
      [[Kategorie:Test]]
      #WEITERLEITUNG [[Andere Seite]]
    WIKI

    FRENCH_ARTICLE = <<~WIKI
      '''Article de test''' est un [[Français|article français]].
      == Section ==
      [[Fichier:Image.jpg|vignette|Description]]
      [[Catégorie:Test]]
      #REDIRECTION [[Autre page]]
    WIKI

    CHINESE_ARTICLE = <<~WIKI
      '''测试文章'''是一个[[中文]]文章。
      == 章节 ==
      [[文件:图片.jpg|缩略图|说明]]
      [[分类:测试]]
      #重定向 [[其他页面]]
    WIKI

    RUSSIAN_ARTICLE = <<~WIKI
      '''Тестовая статья''' — это [[Русский язык|русская]] статья.
      == Раздел ==
      [[Файл:Изображение.jpg|мини|Описание]]
      [[Категория:Тест]]
      #ПЕРЕНАПРАВЛЕНИЕ [[Другая страница]]
    WIKI

    KOREAN_ARTICLE = <<~WIKI
      '''테스트 문서'''는 [[한국어]] 문서입니다.
      == 섹션 ==
      [[파일:Example.jpg|섬네일|설명]]
      [[분류:테스트]]
      #넘겨주기 [[다른 문서]]
    WIKI

    ARABIC_ARTICLE = <<~WIKI
      '''مقالة اختبار''' هي [[اللغة العربية|مقالة عربية]].
      == قسم ==
      [[ملف:صورة.jpg|تصغير|وصف]]
      [[تصنيف:اختبار]]
      #تحويل [[صفحة أخرى]]
    WIKI

    # Edge cases
    EMOJI_CONTENT = "Text with emoji &#x1F600; and &#128512; symbols"
    DEEPLY_NESTED = "{{a|{{b|{{c|{{d|text}}}}}}}}"
    MALFORMED_MARKUP = "[[Unclosed link\n{{Unclosed template"

    # Complex nested structure
    NESTED_TEMPLATES = <<~WIKI
      {{Infobox person
      |name = Test Person
      |birth_date = {{Birth date|1990|1|15}}
      |occupation = [[Scientist]]
      }}
    WIKI

    # Table content
    TABLE_CONTENT = <<~WIKI
      {| class="wikitable"
      |-
      ! Header 1 !! Header 2
      |-
      | Cell 1 || Cell 2
      |}
    WIKI

    # Reference content
    REFERENCE_CONTENT = <<~WIKI
      This is text with a reference.<ref>Citation here</ref>
      Another reference.<ref name="test">Named citation</ref>
    WIKI

    # Multi-line link
    MULTILINE_LINK = <<~WIKI
      [[File:Example.jpg
      |thumb
      |200px
      |A very long caption that spans
      multiple lines]]
    WIKI

    # === Additional Edge Cases for v2.0.0 ===

    # Special characters in titles
    SPECIAL_TITLE_ARTICLE = <<~WIKI
      '''C++ (programming language)''' is a [[programming language]].
      '''O'Brien''' was an [[Irish people|Irish]] person.
      '''Rock & Roll''' is a music genre.
      [[Category:Programming languages]]
    WIKI

    # Very deeply nested templates (10 levels)
    VERY_DEEPLY_NESTED = "{{a|{{b|{{c|{{d|{{e|{{f|{{g|{{h|{{i|{{j|content}}}}}}}}}}}}}}}}}}}}"

    # Mixed multilingual content with emoji
    MIXED_CONTENT = <<~WIKI
      '''Test''' こんにちは 你好 مرحبا Привет 😀
      == Section セクション ==
      Text with emoji: &#x1F600; &#x1F4BB; &#x2764;
      [[Category:Test]][[カテゴリ:テスト]][[分类:测试]]
    WIKI

    # Complex wikilinks with pipes and brackets
    COMPLEX_LINKS = <<~WIKI
      [[File:Photo.jpg|thumb|200px|alt=Alt text|Caption with [[nested link]]]]
      [[Article|Display text with '''bold''' and ''italic'']]
      [[Category:Test|Sort key]]
    WIKI

    # Multiple consecutive templates
    CONSECUTIVE_TEMPLATES = <<~WIKI
      {{Stub}}{{Cleanup}}{{Unreferenced}}
      This article needs work.
      {{Infobox|title=Test}}
    WIKI

    # HTML entities mixed with character references
    HTML_ENTITIES_MIXED = <<~WIKI
      &nbsp;&lt;tag&gt;&amp;&quot;
      &#60;literal&#62;
      &#x3C;hex&#x3E;
      Japanese: &#x65E5;&#x672C;&#x8A9E;
    WIKI

    # Horizontal rules (various lengths)
    HORIZONTAL_RULES = <<~WIKI
      Text before
      ----
      Text between
      --------
      Text after
      --
      Not a rule
      ---
      Also not a rule
    WIKI

    # Headings with various formatting
    COMPLEX_HEADINGS = <<~WIKI
      == Simple Heading ==
      === Heading with [[link]] ===
      ==== Heading with '''bold''' ====
      ===== Heading with trailing space =====
      == 日本語見出し ==
    WIKI

    # Redirect variations
    REDIRECT_VARIATIONS = <<~WIKI
      #REDIRECT [[Target]]
      #redirect [[lowercase]]
      #REDIRECT[[no space]]
      #REDIRECT  [[extra spaces]]
    WIKI
  end
end
