<img src='https://raw.githubusercontent.com/yohasebe/wp2txt/master/image/wp2txt-logo.svg' width="400" />

A command-line toolkit to extract text content and category data from Wikipedia dump files

English | [日本語](README_ja.md)

## Quick Start

```bash
# Install
gem install wp2txt

# Extract text from Japanese Wikipedia (auto-download)
wp2txt --lang=ja -o ./output

# Extract specific articles
wp2txt --lang=ja --articles="東京,京都" -o ./articles

# Extract articles from a category
wp2txt --lang=ja --from-category="日本の都市" -o ./cities
```

## About

WP2TXT extracts plain text and category information from Wikipedia dump files. It processes XML dumps (compressed with bzip2), removes MediaWiki markup, and outputs clean text suitable for corpus linguistics, text mining, and other research purposes.

## Key Features

- **Auto-download** - Automatically download dumps by language code
- **Article extraction by title** - Extract specific articles without downloading full dumps
- **Category-based extraction** - Extract all articles from a specific Wikipedia category
- **Category metadata extraction** - Preserves article category information in output
- **Template expansion** - Expands common templates (dates, units, coordinates) to readable text
- **Multilingual support** - Category and redirect detection for 350+ Wikipedia languages
- **Streaming processing** - Process large dumps without intermediate files
- **JSON output** - Machine-readable JSONL format for data pipelines

## Use Cases

wp2txt is particularly suited for:

- Building domain-specific corpora using category information
- Comparative linguistic research across topic areas
- Extracting Wikipedia text with metadata for NLP tasks
- Cross-linguistic studies using parallel category structures

## Data Access

wp2txt uses [official Wikipedia dump files](https://meta.wikimedia.org/wiki/Data_dumps), the recommended method for bulk data access. This approach respects Wikimedia's infrastructure guidelines.

## Installation

### Install wp2txt

    $ gem install wp2txt

### System Requirements

WP2TXT requires one of the following commands to decompress `bz2` files:

- `lbzip2` (recommended - uses multiple CPU cores)
- `pbzip2`
- `bzip2` (pre-installed on most systems)

On macOS with Homebrew:

    $ brew install lbzip2

On Windows: Install [Bzip2 for Windows](http://gnuwin32.sourceforge.net/packages/bzip2.htm) and add to PATH.

### Docker (Alternative)

```shell
docker run -it -v /path/to/localdata:/data yohasebe/wp2txt
```

The `wp2txt` command is available inside the container. Use `/data` for input/output files.

## Basic Usage

### Auto-download and process (Recommended)

    $ wp2txt --lang=ja -o ./text

This automatically downloads the Japanese Wikipedia dump and extracts plain text. Downloads are cached in `~/.wp2txt/cache/`.

### Extract specific articles by title

    $ wp2txt --lang=ja --articles="認知言語学,生成文法" -o ./articles

Only the index file and necessary data streams are downloaded, making it much faster than processing the full dump.

### Extract articles from a category

    $ wp2txt --lang=ja --from-category="日本の都市" -o ./cities

Include subcategories with `--depth`:

    $ wp2txt --lang=ja --from-category="日本の都市" --depth=2 -o ./cities

Preview without downloading (shows article counts):

    $ wp2txt --lang=ja --from-category="日本の都市" --dry-run

### Process local dump file

    $ wp2txt -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./text

### Other extraction modes

    # Category info only (title + categories)
    $ wp2txt -g --lang=ja -o ./category

    # Summary only (title + categories + opening paragraphs)
    $ wp2txt -s --lang=ja -o ./summary

    # Metadata only (title + section headings + categories)
    $ wp2txt -M --lang=ja --format json -o ./metadata

    # Extract specific sections (comma-separated, 'summary' for lead text)
    $ wp2txt --lang=en --sections="summary,Plot,Reception" --format json -o ./sections

    # Section heading statistics
    $ wp2txt --lang=ja --section-stats -o ./stats

    # JSON/JSONL output
    $ wp2txt --format json --lang=ja -o ./json

## Sample Output

### Text Output

```
[[Article Title]]

Article content goes here with sections and paragraphs...

CATEGORIES: Category1, Category2, Category3
```

### JSON/JSONL Output

Each line contains one JSON object:

```json
{"title": "Article Title", "categories": ["Cat1", "Cat2"], "text": "...", "redirect": null}
```

For redirect articles:

```json
{"title": "NYC", "categories": [], "text": "", "redirect": "New York City"}
```

## Cache Management

    $ wp2txt --cache-status           # Show cache status
    $ wp2txt --cache-clear            # Clear all cache
    $ wp2txt --cache-clear --lang=ja  # Clear cache for Japanese only
    $ wp2txt --update-cache           # Force fresh download

When cache exceeds the expiry period (default: 30 days), wp2txt displays a warning but allows using cached data.

## Wikipedia Dump File (Manual Download)

If you prefer to download manually:

    https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles.xml.bz2

Replace `enwiki` with your target language (e.g., `jawiki` for Japanese). Files are named:

    xxwiki-yyyymmdd-pages-articles.xml.bz2

where `xx` is the language code and `yyyymmdd` is the creation date.

## Advanced Options

### Content Type Markers

Special content is replaced with marker placeholders by default:

**Inline markers** (appear within sentences):

| Marker | Content Type |
|--------|--------------|
| `[MATH]` | Mathematical formulas |
| `[CODE]` | Inline code |
| `[CHEM]` | Chemical formulas |
| `[IPA]` | IPA phonetic notation |

**Block markers** (standalone content):

| Marker | Content Type |
|--------|--------------|
| `[CODEBLOCK]` | Source code blocks |
| `[TABLE]` | Wiki tables |
| `[INFOBOX]` | Information boxes |
| `[NAVBOX]` | Navigation boxes |
| `[GALLERY]` | Image galleries |
| `[REFERENCES]` | Reference lists |
| `[SCORE]` | Musical scores |
| `[TIMELINE]` | Timeline graphics |
| `[GRAPH]` | Graphs/charts |
| `[SIDEBAR]` | Sidebar templates |
| `[MAPFRAME]` | Interactive maps |
| `[IMAGEMAP]` | Clickable image maps |

Configure with `--markers`:

    $ wp2txt --lang=en --markers=all -o ./text        # All markers (default)
    $ wp2txt --lang=en --markers=math,code -o ./text  # Only MATH and CODE

**Note**: `--markers=none` is deprecated as removing special content can make surrounding text nonsensical.

### Template Expansion

Common MediaWiki templates are automatically expanded (enabled by default):

| Template | Output |
|----------|--------|
| `{{birth date\|1990\|5\|15}}` | May 15, 1990 |
| `{{convert\|100\|km\|mi}}` | 100 km (62 mi) |
| `{{coord\|35\|41\|N\|139\|41\|E}}` | 35°41′N 139°41′E |
| `{{lang\|ja\|日本語}}` | 日本語 |
| `{{nihongo\|Tokyo\|東京\|Tōkyō}}` | Tokyo (東京, Tōkyō) |
| `{{frac\|1\|2}}` | 1/2 |
| `{{circa\|1900}}` | c. 1900 |

Supported: date/age templates, unit conversion, coordinates, language tags, quotes, fractions, and more. Parser functions (`{{#if:}}`, `{{#switch:}}`) and magic words (`{{PAGENAME}}`, `{{CURRENTYEAR}}`) are also supported.

Disable with `--no-expand-templates`.

### Citation Extraction

By default, citation templates are removed. Use `--extract-citations` to extract formatted citations:

    $ wp2txt --lang=en --extract-citations -o ./text

Supported: `{{cite book}}`, `{{cite web}}`, `{{cite news}}`, `{{cite journal}}`, `{{Citation}}`, etc.

## Command Line Options

    Usage: wp2txt [options]

    Input source (one of --input or --lang required):
      -i, --input=<s>                  Path to compressed file (bz2) or XML file
      -L, --lang=<s>                   Wikipedia language code (e.g., ja, en, de)
      -A, --articles=<s>               Specific article titles (comma-separated)
      -G, --from-category=<s>          Extract articles from Wikipedia category
      -D, --depth=<i>                  Subcategory recursion depth (default: 0)
      -y, --yes                        Skip confirmation prompt
      --dry-run                        Preview category extraction
      -U, --update-cache               Force refresh of cached files

    Output options:
      -o, --output-dir=<s>             Output directory (default: current)
      -j, --format=<s>                 Output format: text or json (default: text)
      -f, --file-size=<i>              Output file size in MB (default: 10, 0=single)

    Cache management:
      --cache-dir=<s>                  Cache directory (default: ~/.wp2txt/cache)
      --cache-status                   Show cache status and exit
      --cache-clear                    Clear cache and exit

    Configuration:
      --config-init                    Create default config (~/.wp2txt/config.yml)
      --config-path=<s>                Path to configuration file

    Extraction modes (mutually exclusive):
      -g, --category-only              Extract only title and categories
      -s, --summary-only               Extract title, categories, and summary
      -M, --metadata-only              Extract only title, headings, and categories

    Section extraction:
      -S, --sections=<s>               Extract specific sections (comma-separated)
      --section-output=<s>             Output mode: structured or combined (default: structured)
      --min-section-length=<i>         Minimum section length in characters (default: 0)
      --skip-empty                     Skip articles with no matching sections
      --alias-file=<s>                 Custom section alias definitions file (YAML)
      --no-section-aliases             Disable section alias matching (exact match only)
      --section-stats                  Collect and output section heading statistics (JSON)
      --show-matched-sections          Include matched_sections field in JSON output

    Content filtering:
      -a, --category, --no-category    Show category info (default: true)
      -t, --title, --no-title          Keep page titles (default: true)
      -d, --heading, --no-heading      Keep section titles (default: true)
      -l, --list                       Keep list items (default: false)
      --table                          Keep wiki table content (default: false)
      -p, --pre                        Keep preformatted text blocks (default: false)
      -r, --ref                        Keep references as [ref]...[/ref] (default: false)
      --multiline                      Keep multi-line templates (default: false)
      -e, --redirect                   Show redirect destination (default: false)
      -m, --marker, --no-marker        Show list markers (default: true)
      -k, --markers=<s>                Content markers (default: all)
      -C, --extract-citations          Extract formatted citations
      -E, --expand-templates           Expand templates (default: true)
          --no-expand-templates        Disable template expansion

    Performance:
      -n, --num-procs=<i>              Parallel processes (default: auto)
      --no-turbo                       Disable turbo mode (saves disk space, slower)
      -R, --ractor                     Use Ractor parallelism (Ruby 4.0+, streaming only)
      -b, --bz2-gem                    Use bzip2-ruby gem instead of system command

    Output control:
      -q, --quiet                      Suppress progress output (errors only)
      --no-color                       Disable colored output

    Info:
      -v, --version                    Print version
      -h, --help                       Show help

## Configuration File

Create persistent settings with:

    $ wp2txt --config-init

This creates `~/.wp2txt/config.yml`:

```yaml
cache:
  dump_expiry_days: 30      # Days before dumps are stale (1-365)
  category_expiry_days: 7   # Category cache expiry (1-90)
  directory: ~/.wp2txt/cache

defaults:
  format: text              # Default output format
  depth: 0                  # Default subcategory depth
```

Command-line options override configuration file settings.

## Performance

Benchmark results on MacBook Air M4 (7 parallel processes, turbo mode, excluding download time):

| Wikipedia | Dump Size | Articles | Processing Time | Output |
|-----------|-----------|----------|-----------------|--------|
| Japanese  | 4.37 GB   | 1,485,937 | ~27 min        | 463 files (4.5 GB) |
| English   | 24.2 GB   | ~6.8M    | ~2 hours        | 2,000 files (20 GB) |

Turbo mode (default) splits bz2 into XML chunks first, then processes in parallel. Use `--no-turbo` to save disk space at the cost of slower processing.

## Caveats

* Special content (math, code, etc.) is marked with placeholders by default.
* Some text may not be extracted correctly due to markup variations or language-specific formatting.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for detailed release notes.

**v2.0.0 (January 2026)**: Auto-download mode, category-based extraction, article extraction by title, JSON output, content markers, template expansion, streaming processing, Ruby 4.0 support.

## Useful Links

* [Wikipedia Database backup dumps](http://dumps.wikimedia.org/backup-index.html)

## Author

* Yoichiro Hasebe (<yohasebe@gmail.com>)

## References

The author will appreciate your mentioning one of these in your research.

* Yoichiro HASEBE. 2006. [Method for using Wikipedia as Japanese corpus.](http://ci.nii.ac.jp/naid/110006226727) _Doshisha Studies in Language and Culture_ 9(2), 373-403.
* 長谷部陽一郎. 2006. [Wikipedia日本語版をコーパスとして用いた言語研究の手法](http://ci.nii.ac.jp/naid/110006226727). 『言語文化』9(2), 373-403.

BibTeX:

```
@misc{wp2txt_2026,
  author = {Yoichiro Hasebe},
  title = {WP2TXT: A command-line toolkit to extract text content and category data from Wikipedia dump files},
  url = {https://github.com/yohasebe/wp2txt},
  year = {2026}
}
```

## License

This software is distributed under the MIT License. Please see the LICENSE file.
