# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-01-06

### Added

- **Regex cache**: Dynamic regex patterns are now cached to avoid repeated compilation

- **Multilingual category support**: Added support for category namespaces in 30+ languages including:
  - European languages: German (Kategorie), French (Catégorie), Spanish/Italian/Portuguese (Categoria), Dutch (Categorie), Polish (Kategoria), Swedish/Norwegian/Danish (Kategori), Finnish (Luokka), etc.
  - Cyrillic languages: Russian (Категория), Ukrainian (Категорія), Serbian (Категорија), etc.
  - Asian languages: Japanese (カテゴリ), Korean (분류), Chinese Simplified (分类), Chinese Traditional (分類), Thai (หมวดหมู่), Vietnamese (Thể loại), etc.
  - Middle Eastern languages: Arabic (تصنيف), Persian (رده), Hebrew (קטגוריה)

- **Multilingual redirect support**: Added support for redirect keywords in 25+ languages including:
  - European: WEITERLEITUNG (de), REDIRECTION (fr), REDIRECCIÓN (es), RINVIA (it), OMDIRIGERING (sv/no/da), PRZEKIERUJ (pl), OHJAUS (fi), etc.
  - Cyrillic: ПЕРЕНАПРАВЛЕНИЕ (ru), ПЕРЕНАПРАВЛЕННЯ (uk), etc.
  - Asian: 転送 (ja), 넘겨주기 (ko), 重定向 (zh), เปลี่ยนทาง (th), etc.
  - Middle Eastern: تحويل (ar), تغییرمسیر (fa), הפניה (he)

- **Comprehensive test suite**: Added 117 tests covering:
  - Unicode handling (CJK, Cyrillic, Arabic, emoji)
  - Edge cases (deeply nested templates, malformed markup)
  - Multilingual category and redirect extraction
  - Text processing utilities
  - Integration tests with real Wikipedia content

- **SimpleCov integration**: Added code coverage reporting for development

- **Ruby 4.0 compatibility**: Full support for Ruby 4.0

### Changed

- **Performance improvements**:
  - `format_wiki`: Reduced intermediate string allocations by using `gsub!` for in-place modifications
  - `cleanup`: Optimized with `gsub!` to reduce memory allocations
  - `remove_complex`, `make_reference`: Optimized with `gsub!`
  - Category deduplication: Changed from O(n²) to O(n) by calling `uniq!` once at end instead of every line
  - `correct_separator`: Uses `tr` instead of `gsub` for single character replacement
  - `remove_inbetween`: Dynamic regex patterns are now cached

- **BREAKING**: `REMOVE_HR_REGEX` now matches 4 or more hyphens (previously 3+) to align with MediaWiki specification where `----` is the minimum for horizontal rules

- **`chrref_to_utf` function**: Completely rewritten to support all Unicode codepoints (U+0001 to U+10FFFF), including:
  - Supplementary plane characters (emoji, CJK Extension B, etc.)
  - Proper handling of invalid codepoints (returns empty string)

- **`convert_characters` function**: Now uses `String#scrub` for safe handling of invalid UTF-8 sequences instead of calling `exit`

- **`command_exist?` function**: Updated to use `IO.popen` instead of `open("| ...")` for Ruby 4.0 compatibility

### Fixed

- **Unicode BMP limitation**: Fixed `chrref_to_utf` to correctly convert character references beyond the Basic Multilingual Plane (U+FFFF). Previously, emoji like `&#x1F600;` (😀) would produce invalid characters.

- **Encoding error crash**: Fixed `convert_characters` which previously called `exit` on encoding errors, now gracefully handles invalid byte sequences using `scrub`

- **Horizontal rule detection**: Fixed `REMOVE_HR_REGEX` to correctly match MediaWiki horizontal rules (4+ hyphens)

- **Heading regex**: Fixed `IN_HEADING_REGEX` to allow trailing whitespace after closing equal signs

- **Ruby 4.0 compatibility**: Fixed `open("| which cmd")` pattern which no longer works in Ruby 4.0

### Deprecated

- None

### Removed

- None

### Security

- None

## [1.0.2] - Previous releases

See git history for changes prior to 2.0.0.
