# WP2TXT Development Guide

This document provides guidance for developers working on WP2TXT. For user documentation, see [README.md](README.md).

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
| `StreamProcessor` | `lib/wp2txt.rb` | Streams pages from compressed dumps |
| `Article` | `lib/wp2txt/article.rb` | Parses MediaWiki markup |
| `OutputWriter` | `lib/wp2txt.rb` | Manages output file rotation |
| `DumpManager` | `lib/wp2txt/multistream.rb` | Downloads and caches dumps |
| `MultistreamIndex` | `lib/wp2txt/multistream.rb` | Indexes articles for random access |
| `MultistreamReader` | `lib/wp2txt/multistream.rb` | Extracts articles from multistream dumps |
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
# 3. finalize_markers() converts placeholders to [MATH] format
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

### Partial Downloads

For specific article extraction, WP2TXT downloads only necessary data:

```ruby
# Only download first N streams
manager.download_multistream(max_streams: 10)

# Download only needed byte range
download_file_range(url, path, start_byte, end_byte)
```

### Article Extraction Flow

```
1. Download index file (~500MB for en)
2. Load index into hash (O(1) lookup)
3. Find article offsets
4. Group by stream offset
5. Download only needed streams
6. Extract specific articles
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
