# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Auto-download mode**: New `--lang` option automatically downloads Wikipedia dumps:
  - `wp2txt --lang=ja -o ./output` downloads and processes Japanese Wikipedia
  - Downloads cached to `~/.wp2txt/cache/` for reuse
  - Supports any Wikipedia language code (en, ja, de, fr, zh, etc.)

- **Article extraction**: New `--articles` option extracts specific articles by title:
  - `wp2txt --lang=ja --articles="認知言語学,生成文法" -o ./articles`
  - Only downloads index + needed data streams (efficient partial download)
  - O(1) hash lookup for article search

- **Cache management**: New options to manage downloaded dumps:
  - `--cache-status` - Show cache status for all languages
  - `--cache-clear` - Clear all cache
  - `--cache-clear --lang=ja` - Clear cache for specific language
  - `--cache-dir` - Custom cache directory

- **Content type markers**: New `--markers` option marks special content:
  - Supported types: `[MATH]`, `[CODE]`, `[CHEM]`, `[TABLE]`, `[SCORE]`, `[TIMELINE]`, `[GRAPH]`, `[IPA]`, `[INFOBOX]`, `[NAVBOX]`, `[GALLERY]`, `[SIDEBAR]`, `[MAPFRAME]`, `[IMAGEMAP]`, `[REFERENCES]`
  - `--markers=all` (default) - Enable all markers
  - `--markers=none` - Disable markers (content removed)
  - `--markers=math,code` - Enable specific markers only

- **Citation extraction**: New `--extract-citations` (`-C`) option for formatted bibliography output:
  - Extracts author, title, and year from `{{cite book}}`, `{{cite web}}`, `{{Citation}}` templates
  - Formats citations as "Author. \"Title\". Year."
  - Useful for preserving bibliography content instead of removing it
  - Available via CLI (`--extract-citations`) and Ruby API (`extract_citations: true`)

- **Multilingual cleanup**: Automatic removal of MediaWiki artifacts:
  - Magic words: `DEFAULTSORT:`, `DISPLAYTITLE:`, `__NOTOC__`, etc.
  - Interwiki prefixes: `:en:Article` → `Article`
  - Authority control: `Normdaten`, `Authority control`, `Persondata`
  - Category lines in 15+ languages (preserves CATEGORIES summary)
  - Wikimedia project markers: `Wikibooks`, `Commons`, `School:`, etc.

- **Validation framework**: New rake tasks for validating Wikipedia dump processing:
  - `testdata:prepare[lang,level]` - Download and cache test data
  - `validate:run[lang,level]` - Run validation on cached data
  - `validate:full[lang]` - Full dump validation
  - Supports 6 languages: en, zh, ja, ru, ar, ko

- **Multistream support**: New classes for efficient Wikipedia dump processing:
  - `MultistreamIndex` - Parse multistream index files
  - `MultistreamReader` - Extract articles from multistream dumps
  - `DumpManager` - Download and cache dump files
  - `TestDataManager` - Manage test data with auto-refresh
  - `IssueDetector` - Comprehensive validation issue detection

- **MediaWiki data auto-generation**: Magic words and namespace aliases are now fetched from all Wikipedia APIs
  - New script `scripts/fetch_mediawiki_data.rb` queries all 350+ Wikipedia language editions
  - Data stored in `lib/wp2txt/data/mediawiki_aliases.json`
  - 176 redirect keywords, 231 category aliases, 313 file aliases from official MediaWiki sources
  - Image parameters (thumb, left, right, center, etc.) now use 1000+ multilingual aliases
  - All hardcoded language-specific patterns replaced with dynamically loaded data
  - Run `ruby scripts/fetch_mediawiki_data.rb` to update data

### Fixed

- **Pipe trick support**: Links like `[[Wikipedia:Copyright|]]` now correctly display as "Copyright" (removes namespace prefix, disambiguation suffix, and comma-separated location)

- **HTML entity decoding**: Named HTML entities like `&Oslash;` are now properly converted to their Unicode equivalents (Ø)

- **Multi-line template content extraction**: Content following `}}` on the same line is now correctly extracted as a separate paragraph instead of being consumed by the template

## [2.0.0] - 2026-01-07

### Added

- **JSON/JSONL output format**: New `--format json` option outputs articles as JSONL (one JSON object per line) with `title`, `categories`, `text`, and `redirect` fields. Ideal for data pipelines and machine learning workflows.

- **Streaming processing**: Complete rewrite of the processing architecture:
  - No longer creates intermediate XML files
  - Directly streams from bz2 compressed files
  - Reduced disk I/O and storage requirements
  - New `StreamProcessor` and `OutputWriter` classes for modular design

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

- **`--convert` / `-c` option**: No longer needed as streaming processing always converts
- **`--del-interfile` / `-x` option**: No longer needed as intermediate files are no longer created

### Removed

- **Intermediate XML file creation**: The `Splitter` class no longer creates intermediate XML files; processing is now fully streamed

### Security

- None

## [1.0.2] - Previous releases

See git history for changes prior to 2.0.0.
