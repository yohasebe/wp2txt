# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- **Fix: multi-line `<ref>` references broken by element splitting — also fixes `--extract-citations` on multi-line cite templates**: `Article#parse` splits elements at newlines, so any reference written across lines (very common for multi-line `{{cite …}}` templates) had its `[ref]` and `[/ref]` markers land in separate elements, invisible to `remove_ref`. The markers and raw reference markup leaked into the output, and — more importantly — `--extract-citations` silently never fired for multi-line cite templates, producing inconsistent output versus their single-line equivalents. `make_reference` now drops empty references outright and flattens the rest onto a single line before element splitting, so multi-line references behave exactly like single-line ones. Ordinary paragraph breaks outside references are unaffected
- **Fix: `[ref]` markers destroyed by external-link processing**: `process_external_links` stripped the brackets of the `[ref]`/`[/ref]` markers produced by `make_reference` (their contents took the single-word branch), so `remove_ref` could no longer find them and tag names plus reference bodies leaked into extracted text — even with `--ref`, the kept markers came out broken. The markers are now hidden behind placeholders for the duration of the bracket scan and restored afterwards. Downstream corpora no longer contain `ref…/ref` residue, which broke tokenization/sentence splitting and mixed bibliographic text into body prose
- **Runaway-query hardening**: a `query_sql` child process now sets its own kernel-enforced CPU limit (`RLIMIT_CPU`, the query timeout plus a small grace) in addition to the parent's wall-clock kill. Previously a child orphaned by the parent's death — an interrupted test run, a closed terminal, a crashed server — kept executing forever: sqlite3 holds the GVL inside `sqlite3_step`, so Ruby never reaches a signal-safe point and even SIGTERM is ignored. Observed in the wild as two processes spinning at 99% CPU for over five days. The CPU limit is strictly more permissive than the existing wall-clock deadline, so no query that would otherwise succeed is affected
- **Test-suite hang guard**: each example now runs under a wall-clock timeout (120s default; `WP2TXT_SPEC_TIMEOUT=0` disables it, the `:no_timeout` tag exempts an example). The suite deliberately exercises runaway queries, so a wedged example must fail rather than spin

## [2.3.0] - 2026-07-24

- **Documentation split**: README now focuses on text extraction; the research layer (indexes, exhaustive queries, full-text search, langlinks, cross-language SQL, MCP server) is documented in the new [Research Infrastructure Guide](docs/RESEARCH.md), including the complete MCP tool table
- **Container images on GHCR**: images are now published to `ghcr.io/yohasebe/wp2txt` (Docker Hub `yohasebe/wp2txt` is maintained as a mirror)

- **`extract_corpus` `titles:` argument**: Extract an explicit set of article titles (e.g. a set determined via `query_sql`) — titles are normalized (MediaWiki rules), deduplicated preserving input order, and one redirect hop is resolved; missing titles (including redirects to nowhere) are skipped and reported as `not_found` (count + 20-title sample, also in the `.meta.json` sidecar). Mutually exclusive with the filter arguments (set operations belong in SQL); capped at 10,000 titles. The sidecar records `titles_count` + `titles_sha256` (order-independent) for reproducibility, enumerating the full list when ≤100 titles. Also available via `start_extract_job`
- **`query_sql` `output_path:` argument**: Write ALL rows of a large result to a JSONL file (with a `.meta.json` sidecar recording the SQL, dump version, attach configuration, row count, and tool version) and return only a summary + 3-row sample — the extract_corpus D4 pattern generalized to SQL. Writes happen in the forked child (so the 30s SIGKILL deadline covers them) to a `.partial` file that the parent atomically renames on success and removes on every failure path (child crash, timeout kill, query error). Hard cap `SQL_FILE_ROW_LIMIT` = 5M rows (`truncated` flag), cells clipped at 64KB (`cells_clipped` count), duplicate column names are made unique (`_2` suffix), `limit` is ignored in this mode, and existing files require `overwrite: true`. The MCP layer's output-dir confinement is now a shared helper (`Wp2txt::OutputPath.confine`) used by extract_corpus, start_extract_job, and query_sql alike
- **Interlanguage links (`--import-langlinks`)**: Import the official `{lang}wiki-{date}-langlinks.sql.gz` dump into the Tier 1 metadata index as a `langlinks` table (`ll_from` = source page_id, `ll_lang` = target language, `ll_title` = normalized target title). Version pinning is enforced: the langlinks file's dump name must equal the built index's dump version — a mismatch is rejected with no override. Streams the MySQL dump without loading it whole (escape-safe tuple parser, 10k-row transaction batches, indexes created after the load). `--langlinks-langs` restricts imported target languages (e.g. `en,de,fr,zh,ko`); re-import requires `-U` (otherwise a no-op reporting the previous import time). Provenance (source file, size, import time, wp2txt version, language filter, row count) is stamped into the index and reported by `dump_info`; a post-import sanity check samples titles per language and warns when the join rate against a locally installed target edition falls below 90%
- **Multi-dump ATTACH in `query_sql`**: The MCP `query_sql` tool gains an optional `attach` argument (language codes only, never paths): `attach: ["en"]` read-only ATTACHes that language's locally installed metadata DB as `en_meta` and its FTS DB (when built) as `en_fts`, both sharing the main DB's schema. Codes are validated, only installed indexes are accepted, path resolution is server-side (same-date dump preferred; otherwise the latest build with a `dump_mismatch` note in the response's `attached` metadata). User SQL still cannot contain ATTACH/DETACH — attachments are issued by server code only, via `mode=ro` URIs on a read-only connection. Combined with the langlinks table, this enables single-query cross-language comparisons (e.g. section-structure diffs of article pairs)

## [2.2.0] - 2026-07-22

- **Index hardening (design review follow-up)**: `ord` now has identical semantics in `page_sections` and `fts_map` (lead = 0, first heading = 1; schema v2 — rebuild indexes with `--build-index -U`); section headings are normalized identically in both indexes (decorated headings like `== '''X''' ==` now match section filters); indexes record the wp2txt version (and the FTS index a rendering-config digest) so `dump_info` can flag indexes built by code whose text cleaning differs; rebuilds are atomic (built alongside, renamed on completion — a failed rebuild no longer destroys the working index)
- **MCP safety hardening**: `query_sql` runs in a killable subprocess with a 30s wall-clock cap and returns a query-plan diagnosis on timeout; the keyword screen no longer rejects legitimate values inside string literals; `extract_corpus` output paths are confined to the server output directory and refuse to overwrite existing files without `overwrite: true`; background jobs are serialized (one at a time) and all SQLite connections are closed before forking extraction workers
- **Cold-start parity for LLM clients**: closes the gaps that previously required internal knowledge to work around. `get_categories` tool; `find_articles`/`extract_corpus` accept `categories` (exact multi-category AND) and `category_match` (substring on category names); `extract_corpus` gains `content: "wikitext"` for structure mining (infoboxes/templates); `query_sql` read-only SQL escape hatch (SELECT/WITH only, keyword-screened, read-only connection, row/cell caps) with `describe_schema`; article titles are normalized like MediaWiki (underscores, capitalization); `get_article` truncates at `max_chars` (default 40k) with an explicit flag; `dump_info` reports `fulltext_current`
- **Deferred FTS optimize**: `--skip-fts-optimize` skips the single-threaded segment-merge step of the full-text build (the dominant cost on many-core machines: 40-60+ min on a full dump), leaving a fully searchable index; `--fts-optimize` runs the merge later, standalone and idempotent. Optimize state is recorded in index metadata and reported by `dump_info`
- **Full-text search (Tier 2)**: `--build-index --fulltext` builds a contentless SQLite FTS5 index over cleaned section text (tokenizer auto-selected by language: character-trigram for CJK, unicode61 for space-delimited; `--fts-tokenizer` to override, porter stemming opt-in). Search via `--search` (CLI) or the `search_text` MCP tool: literal phrase or raw FTS5 query modes, composable with category recursion and section filters, `count: "capped"|"exact"` (exact 0 = a verified absence claim for the dump version). Snippets are re-rendered from the dump on demand — the index stores no text, keeping disk cost to the inverted index only
- **Background extraction jobs**: `start_extract_job` / `job_status` / `cancel_job` / `list_jobs` MCP tools for extractions beyond the 5000-article synchronous cap. Each job runs in its own thread with isolated resources; extraction now streams to disk in batches (memory-safe at any scale)
- **RAG chunking**: `extract_corpus` accepts `chunk_size` / `chunk_overlap`, emitting one record per chunk with `section_path`, `chunk_index`, and `chunk_count`; chunk boundaries prefer sentence/paragraph breaks
- **Alias guardrail**: `save_alias_set` re-checks co-occurrence server-side and refuses groups containing frequently-coexisting heading pairs (likely distinct roles, not synonyms) unless `force` is passed — protocol compliance no longer depends on the calling model's discipline
- **`discover_aliases` MCP prompt**: bundled recipe walking any agent through the alias verification protocol (discover via `section_stats` → verify via `section_cooccurrence` → sample borderline cases → save)
- **MCP server (`wp2txt-mcp`)**: New binary exposing a local dump to LLM agents via the Model Context Protocol (stdio). Tools: `dump_info`, `get_article`, `get_sections`, `list_headings`, `find_articles`, `category_tree`, `section_stats`, `section_cooccurrence`, `save_alias_set`/`get_alias_set`/`list_alias_sets`, and `extract_corpus` (writes JSONL + reproducibility `.meta.json` sidecar; returns summary and sample only). Requires the `mcp` gem (`gem install mcp`); wp2txt itself does not depend on it
- **LLM-generated section aliases**: Instead of shipping per-language alias dictionaries, agents discover real heading usage with `section_stats`, verify synonym hypotheses with `section_cooccurrence` (synonymous headings almost never co-occur in one article), and persist named alias sets per dump with `save_alias_set`. Queries reference them via `alias_set`; extraction metadata records the exact set contents used
- **`Wp2txt::Corpus` facade**: Shared query/extraction layer used by the MCP server; lazy SQLite-backed title lookup avoids loading multi-million-entry indexes into memory
- **Local metadata index (`--build-index`)**: New offline index built by scanning a multistream dump in parallel. Stores per-article categories, section headings, redirects, and the category hierarchy in SQLite (`~/.wp2txt/cache/*_meta.sqlite3`), keyed to the dump version. No API access required
- **Offline exhaustive queries (`--find-articles`)**: List articles matching `--in-category` (recursive via `--depth`, powered by dump-derived category hierarchy), `--has-section` (alias-aware), and `--title-match` filters. Supports `--limit` and JSON output (`-j json`); redirects are excluded automatically. Enables queries like "all film articles that have a Plot section" against a version-pinned local dump

## [2.1.2] - 2026-07-19

- **Fixed gem file permissions**: The published gem contained files with owner-only (0600) permissions inherited from the build machine, making them unreadable after `sudo gem install`. A `normalize_permissions` task now runs before `rake build`, ensuring all packaged files are world-readable (0644, or 0755 for executables)

## [2.1.1] - 2026-02-21

- **Bidirectional alias matching**: Section extraction now supports reverse alias lookup - specifying an alias name (e.g., "Synopsis") as target matches the canonical heading ("Plot") and vice versa
- **Expanded default section aliases**: Increased from 2 to 12 alias groups covering common English Wikipedia sections (Plot, Reception, References, Bibliography, Awards, Legacy, Early life, Career, etc.)
- **Config forwarding fix**: `--pre`, `--ref`, `--expand-templates`, and `--metadata-only` options now correctly forwarded in `--articles` and `--from-category` modes

## [2.1.0] - 2026-02-19

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

- **CLI option validation**: Extraction modes are now mutually exclusive with clear error messages:
  - `--category-only`, `--summary-only`, `--metadata-only` cannot be combined
  - `--sections` cannot be used with extraction modes
  - `--section-stats` cannot be combined with extraction modes or `--sections`

- **Network retry with exponential backoff**: HTTP requests now retry on transient errors:
  - Retries up to 3 times with exponential backoff (2, 4, 8 seconds)
  - Handles timeouts, connection resets, and DNS failures
  - CategoryFetcher API requests now log failures instead of silently returning nil

- **Disk full error handling**: OutputWriter now handles `Errno::ENOSPC` gracefully:
  - Raises `Wp2txt::FileIOError` with descriptive message on disk full or I/O errors
  - Properly closes file handles before raising

- **File rotation at article boundaries**: OutputWriter `write_from_file` now rotates output files only at blank lines (article boundaries):
  - Prevents articles from being split across output files
  - Eliminates UTF-8 character corruption at file boundaries (e.g., 3-byte Japanese characters split mid-byte)
  - Uses line-by-line reading (`each_line` with `"r:UTF-8"`) instead of fixed-size byte chunks
  - Verified with full Japanese Wikipedia (1.49M articles) and English Wikipedia (24.2 GB) dumps

- **HTTP timeout consistency**: All HTTP methods in `DumpManager` now use `DEFAULT_HTTP_TIMEOUT`:
  - Added `open_timeout`/`read_timeout` to `download_incremental`, `get_remote_file_size`, `download_file_with_progress`, `download_file_range`
  - Previously these methods had no timeout, risking indefinite hangs on network issues

- **Security: Command injection prevention**: All `IO.popen` calls now use array form:
  - Fixed unsafe string interpolation in `wp2txt.rb`, `stream_processor.rb`, `bz2_validator.rb`, `memory_monitor.rb`
  - Prevents shell metacharacter interpretation in file paths

- **Security: SSL certificate verification**: Restored proper TLS certificate validation:
  - Removed `verify_callback` that unconditionally returned `true` (7 locations in `multistream.rb`)
  - `VERIFY_PEER` now performs actual certificate verification

- **Security: Temp file handling**: `file_mod` now uses `Tempfile` instead of hardcoded `"temp"` filename:
  - Prevents predictable file names and potential race conditions
  - Temp files created in same directory as target file

- **CLI option fixes**:
  - Added missing `--table` option (keep wiki table content)
  - Added missing `--multiline` option (keep multi-line templates)
  - Added missing `--pre` option (keep preformatted text blocks)
  - Fixed `--ref` option not being transferred to processing config
  - Reference removal is now conditional (respects `--ref` flag)

- **Ractor turbo mode warning**: Shows explicit warning when `--ractor` is used with turbo mode (unsupported combination)

- **Constants extraction**: Replaced magic numbers with named constants:
  - `DEFAULT_HTTP_TIMEOUT`, `DEFAULT_PROGRESS_INTERVAL`, `INDEX_PROGRESS_THRESHOLD`
  - `DEFAULT_TOP_N_SECTIONS`, `RESUME_METADATA_MAX_AGE_DAYS`, `MAX_HTTP_RETRIES`

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
