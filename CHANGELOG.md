# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- **SQLite-based caching infrastructure**: New high-performance caching using SQLite for faster startup and repeated operations:
  - `GlobalDataCache`: Caches parsed JSON data files (templates, MediaWiki aliases, HTML entities)
    - Eliminates ~500KB JSON parsing overhead on each startup
    - Validates cache against source file modification time and size
    - Location: `~/.wp2txt/cache/global_data.sqlite3`
  - `CategoryCache`: Caches Wikipedia category hierarchy from API
    - Stores category members (pages and subcategories) in SQLite tables
    - Supports recursive tree traversal and bulk page retrieval
    - Per-language cache files: `~/.wp2txt/cache/categories_en.sqlite3`
    - Configurable expiry (default: 7 days)
  - `IndexCache`: Caches parsed multistream index (already existed, now with SQLite3 2.x compatibility)
    - Reduces index parsing from ~10 minutes to seconds on subsequent runs
  - All caches use WAL mode for concurrent read access during parallel processing

- **Ractor parallel processing (Ruby 4.0+)**: New `--ractor` option for thread-based parallelism:
  - Requires Ruby 4.0 or later for stable operation
  - Uses map-join-value pattern for reliable Ractor orchestration
  - ~2x speedup compared to sequential processing
  - Lower memory footprint than process-based parallelism (Parallel gem)
  - Automatic fallback to sequential processing on Ruby 3.x
  - Performance: Parallel gem (~3x) remains faster, Ractor (~2x) uses less memory

- **Template expansion**: New `--expand-templates` (`-E`) option expands common templates to readable text:
  - Date templates: `{{birth date|1990|5|15}}` → "May 15, 1990"
  - Convert templates: `{{convert|100|km|mi}}` → "100 km (62 mi)"
  - Coordinate templates: `{{coord|35|41|N|139|41|E}}` → "35°41′N 139°41′E"
  - Language templates: `{{lang|ja|日本語}}` → "日本語"
  - Quote templates: `{{blockquote|text}}` → "text"
  - And 20+ more template types
  - **Enabled by default** - use `--no-expand-templates` to disable
  - Parser functions support: `{{#if:}}`, `{{#switch:}}`, `{{#ifeq:}}`, `{{#expr:}}`
  - Magic words support: `{{PAGENAME}}`, `{{CURRENTYEAR}}`, `{{NAMESPACE}}`

- **Live article testing**: New test infrastructure fetches real Wikipedia articles:
  - `spec/support/live_articles.rb` - Fetches and caches articles from Wikipedia API
  - `spec/live_article_spec.rb` - Integration tests using live articles
  - Supports known articles for deterministic tests and random sampling for broader coverage
  - Cache with 7-day expiry to minimize API calls
  - Skip with `OFFLINE=1` environment variable

- **Benchmark infrastructure**: New tools for measuring template expansion accuracy:
  - `lib/wp2txt/article_sampler.rb` - Fetches random articles with MediaWiki-rendered text
  - `scripts/benchmark_template_expansion.rb` - Compares wp2txt output against MediaWiki
  - Jaccard similarity scoring for objective comparison
  - Results: 84.5% similarity with template expansion (vs 81.0% without)

- **Removed legacy test data**: Deleted obsolete static test files:
  - `data/testdata_en.bz2` (2.8MB, from 2022)
  - `data/testdata_ja.bz2` (2.6MB, from 2022)
  - `data/output_samples/` directory (~20MB)
  - Tests now use live Wikipedia data with caching

- **Incremental dump downloads**: Smart handling of partial dump files when downloading full dumps:
  - Detects existing partial downloads and offers to resume (download only remaining data)
  - Validates dump dates - if dates match, can resume; if outdated, offers choices
  - User options: resume download, download fresh, keep old partial, or use old as-is
  - Automatic bz2 validation before and after incremental download
  - Falls back to full download if server doesn't support HTTP Range headers

- **bz2 file validation**: New `Bz2Validator` module detects corrupt or invalid bz2 files before processing:
  - Validates magic bytes (`BZ`), version byte (`h`), and block size (`1`-`9`)
  - Optional decompression test to verify file integrity
  - `StreamProcessor` validates bz2 files by default (configurable via `validate_bz2: false`)
  - Detailed error types: `not_found`, `too_small`, `invalid_magic`, `invalid_version`, `invalid_block_size`, `decompression_failed`

- **Memory monitoring**: New `MemoryMonitor` module for adaptive resource management:
  - Cross-platform memory detection (Linux, macOS, Windows)
  - Adaptive buffer sizing based on available memory
  - Memory statistics: `current_memory_usage`, `available_memory`, `memory_usage_percent`
  - Automatic garbage collection when memory is low

- **Parallel article extraction**: `MultistreamReader` now supports parallel processing:
  - `extract_articles_parallel(titles, num_processes: 4)` - Extract multiple articles in parallel
  - `each_article_parallel(entries, num_processes: 4)` - Iterate with parallel processing
  - Automatically groups articles by stream offset to minimize bz2 decompression overhead

- **Performance optimizations**:
  - Pre-compiled 14 additional regex patterns for text cleanup
  - Consolidated gsub chains (3 fewer calls per cleanup operation)
  - Adaptive buffer sizing in `StreamProcessor` based on system memory

- **Cache staleness warnings**: Cache status now shows age and staleness information:
  - Displays cache date and age (e.g., "2025-01-05 - 4 days ago")
  - Warns when cache exceeds configured `dump_expiry_days` (default: 30 days)
  - New `--update-cache` (`-U`) option to force refresh of cached dump files
  - Users can choose to use stale cache or force update

- **Category-based extraction**: New `--from-category` option extracts all articles from a Wikipedia category:
  - `wp2txt --lang=ja --from-category="日本の都市" -o ./output` extracts all articles in the category
  - `--depth` option for subcategory recursion (e.g., `--depth=2` includes 2 levels of subcategories)
  - `--dry-run` for preview mode (shows article counts without downloading)
  - `--yes` to skip confirmation prompt for automation
  - Circular reference prevention for category hierarchies
  - Rate limiting for Wikipedia API requests

- **Configuration file**: New `--config-init` option creates persistent configuration:
  - Settings stored in `~/.wp2txt/config.yml`
  - Configurable: `dump_expiry_days`, `category_expiry_days`, `cache.directory`
  - Default output format and subcategory depth
  - CLI options override config file settings

- **Deprecated `--markers=none`**: Complete removal of special content is now deprecated
  - Removing inline content (e.g., math formulas) makes surrounding text nonsensical
  - `--markers=none` now shows a warning and behaves like `--markers=all`
  - Use `--markers=math,code` to show only specific marker types

- **Marker classification**: Markers now categorized as inline or block
  - **Inline markers** (`[MATH]`, `[CODE]`, `[CHEM]`, `[IPA]`): Content that appears mid-sentence; removal would break grammar
  - **Block markers** (`[TABLE]`, `[CODEBLOCK]`, `[INFOBOX]`, etc.): Standalone content that can be safely removed
  - New `[CODEBLOCK]` marker for `<syntaxhighlight>`, `<source>`, `<pre>` tags (block-level code)
  - `[CODE]` marker now only applies to inline `<code>` tags

## [2.0.0] - 2026-01-08

### Added

- **Auto-download mode**: New `--lang` option automatically downloads Wikipedia dumps:
  - `wp2txt --lang=ja -o ./output` downloads and processes Japanese Wikipedia
  - Downloads cached to `~/.wp2txt/cache/` for reuse
  - Supports any Wikipedia language code (en, ja, de, fr, zh, etc.)

- **Article extraction**: New `--articles` option extracts specific articles by title:
  - `wp2txt --lang=en --articles="Tokyo,Kyoto,Osaka" -o ./articles`
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
  - Available via CLI (`--extract-citations`) and Ruby API (`extract_citations: true`)

- **Multistream support**: New classes for efficient Wikipedia dump processing:
  - `MultistreamIndex` - Parse multistream index files
  - `MultistreamReader` - Extract articles from multistream dumps
  - `DumpManager` - Download and cache dump files
  - Enables targeted article extraction without downloading full dump

- **Validation framework**: New rake tasks for validating Wikipedia dump processing:
  - `testdata:prepare[lang,level]` - Download and cache test data
  - `validate:run[lang,level]` - Run validation on cached data
  - `validate:full[lang]` - Full dump validation

- **HTML entity management**: Comprehensive entity support from authoritative sources:
  - 2125 entities from WHATWG HTML specification (`html_entities.json`)
  - Wikipedia-specific entities (`wikipedia_entities.json`): `&ratio;`, `&dash;`, `&nbso;`
  - New script `scripts/fetch_html_entities.rb` to update from WHATWG
  - Replaces hardcoded entity list with data-driven approach

- **MediaWiki data auto-generation**: Magic words and namespace aliases fetched from all Wikipedia APIs:
  - New script `scripts/fetch_mediawiki_data.rb` queries 350+ Wikipedia language editions
  - Data stored in `lib/wp2txt/data/mediawiki_aliases.json`
  - 176 redirect keywords, 231 category aliases, 313 file aliases
  - Run `ruby scripts/fetch_mediawiki_data.rb` to update

- **JSON/JSONL output format**: New `--format json` option outputs articles as JSONL (one JSON object per line) with `title`, `categories`, `text`, and `redirect` fields. Ideal for data pipelines and machine learning workflows.

- **Streaming processing**: Complete rewrite of the processing architecture:
  - No longer creates intermediate XML files
  - Directly streams from bz2 compressed files
  - Reduced disk I/O and storage requirements
  - New `StreamProcessor` and `OutputWriter` classes for modular design

- **Regex cache**: Dynamic regex patterns are now cached to avoid repeated compilation

- **Multilingual category support**: Added support for category namespaces in 30+ languages (European, Cyrillic, Asian, Middle Eastern)

- **Multilingual redirect support**: Added support for redirect keywords in 25+ languages

- **Comprehensive test suite**: 395 tests covering:
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

- **Unicode BMP limitation**: Fixed `chrref_to_utf` to correctly convert character references beyond the Basic Multilingual Plane (U+FFFF). Previously, emoji like `&#x1F600;` would produce invalid characters.

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
