# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries were rewritten in August 2026 to describe what changed for people using
wp2txt, rather than how it was implemented. The changes themselves are unaltered.

## [2.3.1] - 2026-08-12

- **Fix: references leaked into extracted text**: reference contents — tag remnants like `ref…/ref` and the bibliographic text inside them — could end up in the extracted body text, breaking sentence splitting and mixing citation details into running prose. In a spot check of five English articles this affected about 70 places per article. References are now removed cleanly (or kept intact as `[ref]…[/ref]` with `--ref`), including references written across several lines and empty ones
- **Fix: `--extract-citations` ignored multi-line citation templates**: a `{{cite …}}` template split over several lines was left as raw markup instead of being formatted, so citations extracted from such references were silently missing. Single-line and multi-line templates now produce the same result
- **Long-running queries can no longer outlive their timeout**: an interrupted session could leave a `query_sql` process running at full CPU indefinitely. Queries now stop on their own even if the process that started them goes away. Queries that complete within the time limit are unaffected
- **Container images move to GitHub Container Registry**: images are published to `ghcr.io/yohasebe/wp2txt` only. The Docker Hub repository is no longer updated — please switch:

      docker pull ghcr.io/yohasebe/wp2txt

## [2.3.0] - 2026-07-24

- **Extract an explicit list of articles**: `extract_corpus` accepts `titles:` — hand it the set you arrived at some other way (a `query_sql` result, your own list) instead of describing it with filters again. Titles are normalized the way MediaWiki treats them, duplicates are dropped, and one redirect hop is followed. Titles with no article are skipped and reported back as `not_found`, so a missing article is visible rather than silently absent. Up to 10,000 titles; cannot be combined with the filter arguments. Also available through `start_extract_job`
- **Write a large SQL result to a file**: `query_sql` accepts `output_path:` — all rows go to a JSONL file and the reply carries a summary plus three sample rows, instead of a row cap. The file is written completely or not at all: an interrupted or failing query leaves no partial output. Up to 5 million rows, cells longer than 64KB are clipped (both are reported back), and an existing file is only replaced with `overwrite: true`. A `.meta.json` beside the output records the SQL, the dump versions involved, and the row count
- **Interlanguage links (`--import-langlinks`)**: import the official `langlinks` dump into the metadata index to map articles across editions. The langlinks file must carry the same dump date as your index — a mismatch is refused, so links can never be mixed across versions. `--langlinks-langs en,de,fr,zh,ko` limits which target languages are imported; re-importing requires `-U`. After the import, a sample of titles per language is checked against any editions you have installed and the match rate is reported. `dump_info` shows what was imported and when
- **Query several editions in one statement**: `query_sql` accepts `attach: ["en"]`, which makes that language's index available as `en_meta` (and `en_fts` where a full-text index exists) alongside your own. You pass language codes, not paths, and only editions you have installed are accepted. The reply lists what was attached, including each edition's dump name, and says so when the dates differ. Together with the `langlinks` table this makes cross-edition comparisons a single query
- **Documentation split**: the README now covers text extraction; the index and MCP features (indexes, offline queries, full-text search, interlanguage links, cross-language SQL, MCP server) moved to a separate guide — now [docs/INDEXES.md](docs/INDEXES.md) — which lists every MCP tool
- **Container images on GitHub Container Registry**: images are now published to `ghcr.io/yohasebe/wp2txt`

## [2.2.0] - 2026-07-22

- **Index format change — rebuild existing indexes with `--build-index -U`** (schema v2). Section headings are now recorded consistently, so headings written with decoration (`== '''X''' ==`) match section filters instead of being missed. Each index records the wp2txt version that built it, and `dump_info` warns when an index was built by a version whose text cleaning differs from the one you are running. A rebuild that fails partway no longer destroys the index you already had
- **Safer defaults for MCP use**: `query_sql` stops after 30 seconds and explains what made the query slow; queries containing words like `Update` inside a quoted value are no longer rejected by mistake. `extract_corpus` can only write under the server's output directory and will not replace an existing file unless you pass `overwrite: true`. Background jobs run one at a time
- **More ways to select articles from an LLM client**: a `get_categories` tool; `categories` (article must be in all of them) and `category_match` (substring on category names) on `find_articles` and `extract_corpus`; `content: "wikitext"` on `extract_corpus` for reading infoboxes and templates that cleaned text replaces with markers; `query_sql` for read-only SQL when the fixed tools cannot express a question, with `describe_schema` to see the tables. Article titles are matched the way MediaWiki treats them (underscores, capitalization). `get_article` stops at `max_chars` (default 40,000) and says when it truncated; `dump_info` reports whether the full-text index is up to date
- **Split the full-text build in two**: `--skip-fts-optimize` leaves out the final merge step — the slowest part on a full dump, 40–60 minutes and single-threaded — and still gives you a searchable index. Run `--fts-optimize` later when convenient; it is safe to repeat. `dump_info` shows whether the merge has been done
- **Full-text search**: `--build-index --fulltext` adds a searchable index over the cleaned article text. The tokenizer is chosen by language (character trigrams for Japanese, Chinese, Korean; word-based elsewhere, `--fts-tokenizer` to override). Search from the CLI with `--search` or from an LLM client with `search_text`, combined with category and section filters, as a literal phrase or a full-text query. Counts can be capped for speed or exact — an exact `0` means the term is absent from that dump. The index stores no article text (snippets are re-read from the dump when needed), so it costs far less disk than a copy of the corpus
- **Background extraction jobs**: `start_extract_job` / `job_status` / `cancel_job` / `list_jobs` for extractions beyond the 5,000-article limit of a direct call. Extraction writes to disk as it goes, so memory use no longer grows with the size of the job
- **Chunked output for RAG**: `extract_corpus` accepts `chunk_size` / `chunk_overlap` and emits one record per chunk with its `section_path`, `chunk_index`, and `chunk_count`. Chunks prefer to break at sentence and paragraph boundaries
- **Alias sets are checked before they are saved**: `save_alias_set` refuses a group whose headings frequently appear together in the same article — a sign they are different sections rather than synonyms — unless you pass `force`
- **`discover_aliases` prompt**: a bundled walkthrough of finding heading variants (`section_stats` → `section_cooccurrence` → save), so you do not have to remember the steps
- **MCP server (`wp2txt-mcp`)**: a new command that exposes a local dump to an LLM client over the Model Context Protocol. Tools cover dump identity, single articles and their sections, filtered listings, category trees, heading statistics, alias sets, and extraction to JSONL with a `.meta.json` recording the dump version and query. Requires the `mcp` gem (`gem install mcp`); wp2txt itself does not depend on it
- **Section aliases come from the dump, not from a bundled dictionary**: find the headings actually used with `section_stats`, check whether two of them mean the same thing with `section_cooccurrence`, and save the group with `save_alias_set`. Queries then refer to it by name via `alias_set`, and extractions record which group was used
- **Ruby API**: `Wp2txt::Corpus` provides the query and extraction layer used by the MCP server, for embedding wp2txt in your own code. Title lookup reads from SQLite on demand rather than loading a multi-million-entry index into memory
- **Offline metadata index (`--build-index`)**: builds a local index of a dump — each article's categories, section headings, redirects, and the category hierarchy — by scanning it in parallel. Stored under `~/.wp2txt/cache/` and tied to the dump version. No API access needed
- **Offline queries over a whole edition (`--find-articles`)**: list articles by `--in-category` (with `--depth` to include subcategories), `--has-section` (alias-aware), and `--title-match`. Supports `--limit` and JSON output (`-j json`); redirects are excluded. This is what makes questions like "all film articles that have a plot section" answerable against a pinned dump

## [2.1.2] - 2026-07-19

- **Fixed unreadable files after `sudo gem install`**: files in the published gem carried owner-only permissions, so wp2txt failed to run for anyone but the installing user. Packaged files are now readable by everyone (0644, and 0755 for executables). If you hit this, reinstall the gem

## [2.1.1] - 2026-02-21

- **Section aliases match in both directions**: asking for "Synopsis" now also finds sections headed "Plot", and the other way round, instead of only matching the name you happened to type
- **More section aliases out of the box**: 12 groups instead of 2, covering common English Wikipedia sections (Plot, Reception, References, Bibliography, Awards, Legacy, Early life, Career, and others)
- **Fixed options being ignored**: `--pre`, `--ref`, `--expand-templates`, and `--metadata-only` had no effect when used with `--articles` or `--from-category`. They now apply in those modes too

## [2.1.0] - 2026-02-19

- **Faster startup and repeated runs**: parsed data files, the Wikipedia category hierarchy (per language, 7-day expiry), and the multistream dump index are now cached under `~/.wp2txt/cache/`. Re-reading the index of a full dump used to take ~10 minutes; later runs now start in seconds
- **`--ractor` (Ruby 4.0+)**: thread-based parallel processing — about 2× faster than sequential, with a smaller memory footprint than the default process-based mode (which remains the fastest at ~3×). On Ruby 3.x the option falls back to sequential processing
- **Templates are expanded into readable text by default**: dates (`{{birth date|1990|5|15}}` → "May 15, 1990"), unit conversions (`{{convert|100|km|mi}}` → "100 km (62 mi)"), coordinates, language tags (`{{lang|ja|日本語}}` → 日本語), quotes, and 20+ more, plus common parser functions (`{{#if:}}`, `{{#switch:}}`) and magic words (`{{PAGENAME}}`). Turn off with `--no-expand-templates`
- **Interrupted downloads resume**: a partial dump download is detected and, when the server supports it, only the remaining data is fetched. If the dump date has changed you are asked whether to resume, redownload, or keep the old file; files are validated before and after
- **Corrupt dump files are detected before processing** instead of failing partway through, with the specific reason reported (file truncated, not a bz2 file, failed decompression test)
- **Output files rotate at article boundaries**: an article is never split across two output files, and multi-byte characters are no longer corrupted at file boundaries. Verified against the full Japanese (1.49M articles) and English (24.2 GB) dumps
- **Downloads can no longer hang indefinitely**: every network operation now has a timeout (several previously had none)
- **Transient network errors retry automatically** (3 attempts with 2/4/8-second backoff) instead of failing the run, and failed category API requests are logged instead of silently returning nothing
- **Running out of disk space raises a clear error** instead of leaving corrupt output behind
- **Cache age is visible**: cache listings show the date and age of each cached dump and warn when it exceeds `dump_expiry_days` (default 30); `--update-cache` (`-U`) forces a refresh
- **`--from-category`**: extract every article in a Wikipedia category via the Wikipedia API, with `--depth` for subcategory levels, `--dry-run` to preview article counts before downloading, and `--yes` for unattended runs
- **`--config-init`**: writes a persistent configuration file to `~/.wp2txt/config.yml` (cache lifetimes, cache directory, output defaults). Command-line options still take precedence
- **`--markers=none` is deprecated**: removing inline content (a formula mid-sentence) leaves broken text, so the option now warns and behaves like `--markers=all`. Use `--markers=math,code` to keep only specific marker types
- **Markers are classified as inline or block**: inline markers (`[MATH]`, `[CODE]`, `[CHEM]`, `[IPA]`) stand in for content whose removal would break the sentence; block markers (`[TABLE]`, `[INFOBOX]`, …) replace standalone content. New `[CODEBLOCK]` marker for code blocks; `[CODE]` now covers only inline code
- **Conflicting options are rejected with a clear message**: `--category-only`, `--summary-only`, and `--metadata-only` are mutually exclusive, and `--sections` / `--section-stats` cannot be combined with them
- **Option fixes**: `--table`, `--multiline`, and `--pre` were missing from the CLI and are now available; `--ref` was accepted but had no effect — reference removal now respects it
- `--ractor` combined with turbo mode now warns explicitly (the combination is unsupported)
- **Security fixes**: file paths are no longer passed through a shell, so crafted path names cannot inject commands; TLS certificate verification is actually performed (it was previously disabled by an accept-everything callback); temporary files use unpredictable names instead of a fixed name in the working directory
- **Performance**: text cleanup is faster (fewer passes over each article), and buffer sizes adapt to the memory actually available on the machine
- **Ruby API**: articles can be extracted from a multistream dump in parallel (`extract_articles_parallel`, `each_article_parallel`), grouped by stream to avoid decompressing the same block twice

## [2.0.0] - 2026-01-08

### Added

- **`--lang`**: downloads the Wikipedia dump for any language code and processes it in one step (`wp2txt --lang=ja -o ./output`). Downloads are cached under `~/.wp2txt/cache/` for reuse
- **`--articles`**: extract specific articles by title (`wp2txt --lang=en --articles="Tokyo,Kyoto,Osaka" -o ./articles`), downloading only the index and the data streams that contain them rather than the whole dump
- **Cache management**: `--cache-status` (per-language overview), `--cache-clear` (all languages, or one with `--lang`), and `--cache-dir` (custom location)
- **Content markers (`--markers`)**: special content is replaced by a marker instead of disappearing silently: `[MATH]`, `[CODE]`, `[CHEM]`, `[TABLE]`, `[SCORE]`, `[TIMELINE]`, `[GRAPH]`, `[IPA]`, `[INFOBOX]`, `[NAVBOX]`, `[GALLERY]`, `[SIDEBAR]`, `[MAPFRAME]`, `[IMAGEMAP]`, `[REFERENCES]`. `--markers=all` is the default; `--markers=math,code` keeps only the listed types
- **Citation extraction (`--extract-citations`, `-C`)**: outputs a formatted bibliography ("Author. \"Title\". Year.") from `{{cite book}}`, `{{cite web}}`, and `{{Citation}}` templates. Also available from the Ruby API (`extract_citations: true`)
- **JSON/JSONL output (`--format json`)**: one JSON object per line with `title`, `categories`, `text`, and `redirect` fields, for data pipelines and machine-learning workflows
- **Multistream dumps are handled natively**, which is what makes targeted extraction work without downloading a full dump. Ruby API: `MultistreamIndex`, `MultistreamReader`, `DumpManager`
- **HTML character entities are converted comprehensively**: 2,125 entities from the WHATWG HTML specification, plus Wikipedia-specific ones (`&ratio;`, `&dash;`, `&nbso;`)
- **Redirect, category, and file keywords fetched from 350+ Wikipedia language editions** (176 redirect keywords, 231 category aliases, 313 file aliases), replacing a small hardcoded list
- **Categories are recognized in 30+ languages** (European, Cyrillic, Asian, and Middle Eastern scripts) and **redirects in 25+**
- **Fully streamed processing**: dumps are processed directly from the compressed file, with no intermediate XML files — far less disk space and I/O than before
- **Ruby 4.0 support**

### Changed

- **BREAKING: horizontal rules now require 4 or more hyphens** (previously 3), matching the MediaWiki specification — a line of `---` in an article is now treated as content, not as a rule
- **Character references convert across the entire Unicode range** (U+0001–U+10FFFF), including emoji and supplementary-plane CJK; invalid codepoints become empty strings instead of garbage characters
- **Faster text processing**: category deduplication went from quadratic to linear time, and string handling allocates far less memory on large articles

### Fixed

- **Character references beyond U+FFFF now produce the right character**: `&#x1F600;` becomes 😀 instead of an invalid character
- **Invalid UTF-8 in a dump no longer aborts the run**: bad byte sequences are scrubbed and processing continues (the tool previously exited mid-run)
- **Headings with trailing whitespace** after the closing `==` are now recognized as headings

### Deprecated

- **`--convert` / `-c`**: no longer needed — streaming processing always converts
- **`--del-interfile` / `-x`**: no longer needed — intermediate files are no longer created

### Removed

- **Intermediate XML files**: processing no longer writes intermediate XML next to the output at any point

### Security

- None

## [1.0.2] - Previous releases

See git history for changes prior to 2.0.0.
