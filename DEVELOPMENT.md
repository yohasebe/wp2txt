# WP2TXT Development Guide

This document provides guidance for developers working on WP2TXT. For user documentation, see [README.md](README.md).

English | [日本語](DEVELOPMENT_ja.md)

## Quick Start

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run tests with coverage
bundle exec rspec  # Coverage report at coverage/index.html
```

## Architecture Overview

### Processing Pipeline

WP2TXT uses a streaming architecture to process Wikipedia dumps:

```
Input (bz2/xml) → StreamProcessor → Article Parser → OutputWriter → Output files
```

1. **StreamProcessor** (`lib/wp2txt.rb`): Decompresses bz2 and streams XML pages
2. **Article** (`lib/wp2txt/article.rb`): Parses MediaWiki text into typed elements
3. **Utils** (`lib/wp2txt/utils.rb`): Provides text formatting and cleanup functions
4. **OutputWriter** (`lib/wp2txt.rb`): Writes output in text or JSON format

### Core Classes

| Class | File | Purpose |
|-------|------|---------|
| `StreamProcessor` | `lib/wp2txt/stream_processor.rb` | Streams pages from compressed dumps with adaptive buffering |
| `Article` | `lib/wp2txt/article.rb` | Parses MediaWiki markup |
| `OutputWriter` | `lib/wp2txt.rb` | Manages output file rotation |
| `DumpManager` | `lib/wp2txt/multistream.rb` | Downloads and caches dumps |
| `MultistreamIndex` | `lib/wp2txt/multistream.rb` | Indexes articles for random access |
| `MultistreamReader` | `lib/wp2txt/multistream.rb` | Extracts articles (supports parallel extraction) |
| `MemoryMonitor` | `lib/wp2txt/memory_monitor.rb` | Cross-platform memory monitoring |
| `Bz2Validator` | `lib/wp2txt/bz2_validator.rb` | Validates bz2 file integrity |
| `CLI` | `lib/wp2txt/cli.rb` | Command-line option parsing |

### Element Types

The `Article` class parses MediaWiki text into typed elements:

| Type | Description |
|------|-------------|
| `:mw_heading` | Section headings (`== Title ==`) |
| `:mw_paragraph` | Regular text paragraphs |
| `:mw_table` | Wiki tables (`{| ... |}`) |
| `:mw_quote` | Block quotes |
| `:mw_pre` | Preformatted text |
| `:mw_unordered` | Unordered list items |
| `:mw_ordered` | Ordered list items |
| `:mw_definition` | Definition list items |
| `:mw_link` | Single-line links |
| `:mw_ml_link` | Multi-line links |
| `:mw_redirect` | Redirect pages |
| `:mw_template` | Templates |
| `:mw_isolated_tag` | HTML tags |

### Marker System

Content type markers replace special content (math, code, etc.) with placeholders:

```ruby
# In utils.rb
MARKER_TYPES = %i[math code chem table score timeline graph ipa].freeze

# Processing flow:
# 1. Content detected → Replace with placeholder («« MATH »»)
# 2. Text processing continues (placeholders protected from cleanup)
# 3. finalize_markers() converts placeholders to [MARKER] format
```

### Magic Word Expansion

The `MagicWordExpander` class (`lib/wp2txt/magic_words.rb`) expands MediaWiki magic words to their actual values:

| Category | Magic Words | Example |
|----------|-------------|---------|
| Page context | `PAGENAME`, `FULLPAGENAME`, `BASEPAGENAME`, `ROOTPAGENAME`, `SUBPAGENAME`, `NAMESPACE`, `TALKPAGENAME` | `{{PAGENAME}}` → "Article Title" |
| Date/time | `CURRENTYEAR`, `CURRENTMONTH`, `CURRENTDAY`, `CURRENTDAYNAME`, `CURRENTTIME`, `CURRENTTIMESTAMP` | `{{CURRENTYEAR}}` → "2024" |
| String functions | `lc`, `uc`, `lcfirst`, `ucfirst`, `urlencode`, `anchorencode`, `padleft`, `padright` | `{{uc:hello}}` → "HELLO" |
| Parser functions | `#titleparts` | `{{#titleparts:A/B/C\|2}}` → "A/B" |

Magic words are expanded early in the `format_wiki()` pipeline when a title is provided in the config:

```ruby
result = format_wiki(text, title: "Article Name", dump_date: Time.now)
```

## Test System

### Test Structure

```
spec/
├── spec_helper.rb          # RSpec configuration
├── article_spec.rb         # Article parsing tests
├── utils_spec.rb           # Text processing tests
├── markers_spec.rb         # Marker functionality tests
├── auto_download_spec.rb   # CLI and download tests
├── multilingual_spec.rb    # Language-specific tests
├── streaming_spec.rb       # Streaming architecture tests
└── testdata/               # Static test data
```

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/utils_spec.rb

# Run with documentation format
bundle exec rspec --format documentation

# Run specific test by line number
bundle exec rspec spec/utils_spec.rb:42
```

## Test Data Management

WP2TXT includes tools for managing test data from real Wikipedia dumps.

### Test Data Rake Tasks

```bash
# Show cache status
rake testdata:status

# Download and cache test data for a language
rake testdata:prepare[ja,10]     # 10 streams (~500-1000 articles)

# Prepare all core languages
rake testdata:prepare_all[10]

# Tier-based preparation (for comprehensive testing)
rake testdata:tier_status
rake testdata:prepare_tier[tier1]
rake testdata:prepare_all_tiers
```

### Language Tiers

Languages are organized into tiers for testing:

| Tier | Languages | Sample Size |
|------|-----------|-------------|
| Tier 1 | en, ja, zh, de, fr, es | 500 articles |
| Tier 2 | ru, pt, it, ar, ko, nl, etc. | 200 articles |
| Tier 3 | Other major languages | 100 articles |
| Tier 4 | Smaller Wikipedias | 50 articles |

### Cache Location

Test data is cached in `tmp/test_cache/`:

```
tmp/test_cache/
├── dumps/              # Downloaded dump files
│   ├── jawiki-*-multistream.xml.bz2
│   └── jawiki-*-multistream-index.txt.bz2
├── ja/
│   └── test_10streams.json
└── en/
    └── test_10streams.json
```

## Validation System

The validation system detects issues in text processing.

### Running Validation

```bash
# Validate cached test data
rake validate:run[ja,10]

# Validate all languages
rake validate:run_all[10]

# Full dump validation (takes hours)
rake validate:full[ja]

# Generate report from logs
rake validate:report[tmp/validation/ja_10streams_20260107.jsonl]

# Tier-based validation
rake validate:tier[tier1]
rake validate:all_tiers
```

### Issue Types Detected

The `IssueDetector` class (`lib/wp2txt/test_data_manager.rb`) detects:

- **leftover_markup**: Unprocessed MediaWiki markup in output
- **unbalanced_brackets**: Mismatched `[[`, `]]`, `{{`, `}}`
- **broken_encoding**: Invalid UTF-8 characters
- **empty_output**: Articles with no extracted content
- **excessive_whitespace**: Multiple consecutive blank lines

### Validation Output

Validation logs are saved to `tmp/validation/` in JSONL format:

```json
{"title": "Article Name", "issues": [{"type": "leftover_markup", "context": "..."}]}
```

## Multistream Support

WP2TXT supports Wikipedia's multistream format for efficient article extraction.

### How Multistream Works

1. **Index file** (`-multistream-index.txt.bz2`): Maps article titles to byte offsets
2. **Multistream file** (`-multistream.xml.bz2`): Concatenated bz2 streams

### Parallel Extraction

`MultistreamReader` supports parallel article extraction for improved performance:

```ruby
reader = MultistreamReader.new(multistream_path, index_path)

# Extract multiple articles in parallel (4 processes by default)
results = reader.extract_articles_parallel(["Tokyo", "Kyoto", "Osaka"], num_processes: 4)

# Iterate with parallel processing
reader.each_article_parallel(entries, num_processes: 4) do |page|
  process(page)
end
```

Articles are grouped by stream offset to minimize bz2 decompression overhead.

### Partial Downloads

For specific article extraction, WP2TXT downloads only necessary data:

```ruby
# Only download first N streams
manager.download_multistream(max_streams: 10)

# Download only needed byte range
download_file_range(url, path, start_byte, end_byte)
```

### Incremental Downloads

When a partial dump exists, `download_multistream_full` can resume the download:

```ruby
manager = DumpManager.new("ja")

# Check for existing partial dump
partial = manager.find_any_partial_cache
# => { path: "...", dump_date: "20260101", stream_count: 100, size: 1000000, mtime: ... }

# Check if incremental download is possible
resume_info = manager.can_resume_from_partial?(partial)
# => { possible: true, current_streams: 100, total_streams: 5000, current_size: 1000000 }
# => { possible: false, reason: :date_mismatch, partial_date: "20250101", latest_date: "20260101" }

# Download full dump with incremental support (interactive prompts)
path = manager.download_multistream_full(interactive: true)

# Non-interactive mode (skips user prompts, always downloads fresh if needed)
path = manager.download_multistream_full(interactive: false)
```

User prompts for incremental downloads:

1. **Same date partial exists:**
   - `[Y]` Resume download (download only remaining data)
   - `[n]` Use existing partial as-is
   - `[f]` Download fresh full dump

2. **Outdated partial exists:**
   - `[D]` Delete old partial and download latest (recommended)
   - `[k]` Keep old partial, download latest separately
   - `[u]` Use old partial as-is (may have outdated content)

### Article Extraction Flow

```
1. Download index file (~500MB for en)
2. Load index into hash (O(1) lookup)
3. Find article offsets
4. Group by stream offset
5. Download only needed streams
6. Extract specific articles
```

## Memory Management

WP2TXT includes adaptive memory management for processing large dumps:

### MemoryMonitor

Cross-platform memory monitoring in `lib/wp2txt/memory_monitor.rb`:

```ruby
# Check current memory usage
stats = Wp2txt::MemoryMonitor.memory_stats
# => { current: 256000000, available: 8000000000, ... }

# Get optimal buffer size based on available memory
buffer_size = Wp2txt::MemoryMonitor.optimal_buffer_size
# => 10485760 (10 MB)

# Check if memory is low and trigger GC if needed
Wp2txt::MemoryMonitor.gc_if_needed
```

### StreamProcessor Adaptive Buffering

`StreamProcessor` adjusts buffer size dynamically:

```ruby
processor = Wp2txt::StreamProcessor.new(input_path, adaptive_buffer: true)
processor.each_page { |title, text| ... }

# Monitor processing stats
processor.stats
# => { pages_processed: 1000, bytes_read: 50000000, buffer_size: 10485760, ... }
```

## bz2 Validation

The `Bz2Validator` module validates bz2 files before processing:

```ruby
# Full validation (header + decompression test)
result = Wp2txt::Bz2Validator.validate("/path/to/file.bz2")
result.valid?      # => true/false
result.error_type  # => :invalid_magic, :too_small, etc.
result.message     # => "Invalid bz2 header..."

# Quick validation (header only)
result = Wp2txt::Bz2Validator.validate_quick("/path/to/file.bz2")

# Get file info
info = Wp2txt::Bz2Validator.file_info("/path/to/file.bz2")
# => { path: "...", size: 1000000, valid_header: true, version: "h", block_size: 9, ... }
```

## Adding New Features

### Adding a New Marker Type

1. Add to `MARKER_TYPES` in `lib/wp2txt/utils.rb`
2. Add detection pattern in `apply_markers()`
3. Add tests in `spec/markers_spec.rb`

### Adding a New CLI Option

1. Add option definition in `lib/wp2txt/cli.rb`
2. Add validation in `validate_options!()`
3. Handle option in `bin/wp2txt`
4. Add tests in `spec/auto_download_spec.rb`
5. Update README.md

### Adding Language Support

1. Category keywords: `data/language_categories.json`
2. Redirect keywords: `data/language_redirects.json`
3. Scripts: `scripts/generate_language_data.rb`

## Code Style

- Ruby 2.6+ compatibility
- Frozen string literals (`# frozen_string_literal: true`)
- RuboCop configuration in `.rubocop.yml`
- UTF-8 encoding throughout

## Docker

Build and push Docker images:

```bash
rake push  # Builds multi-arch and pushes to Docker Hub
```

## Release Process

1. Update version in `lib/wp2txt/version.rb`
2. Update CHANGELOG.md
3. Run full test suite: `bundle exec rspec`
4. Build gem: `gem build wp2txt.gemspec`
5. Push to RubyGems: `gem push wp2txt-*.gem`
6. Push Docker image: `rake push`
7. Create GitHub release

## Useful Links

- [MediaWiki Markup Reference](https://www.mediawiki.org/wiki/Help:Formatting)
- [Wikipedia Dump Downloads](https://dumps.wikimedia.org/)
- [Multistream Format](https://meta.wikimedia.org/wiki/Data_dumps/FAQ#Why_are_there_multiple_files_for_a_single_dump?)
