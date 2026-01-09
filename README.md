<img src='https://raw.githubusercontent.com/yohasebe/wp2txt/master/image/wp2txt-logo.svg' width="400" />

A command-line toolkit to extract text content and category data from Wikipedia dump files

English | [日本語](README_ja.md)

## Why wp2txt?

There are several tools for extracting plain text from Wikipedia dumps. [WikiExtractor](https://github.com/attardi/wikiextractor) is a popular Python-based tool known for its speed. However, **wp2txt offers unique features that WikiExtractor does not provide**:

| Feature | wp2txt | WikiExtractor |
|---------|--------|---------------|
| Plain text extraction | ✅ | ✅ |
| **Category metadata extraction** | ✅ | ❌ |
| **Category-based article extraction** | ✅ | ❌ |
| Category-only output (`-g`) | ✅ | ❌ |
| **Specific article extraction by title** | ✅ | ❌ |
| Section headings | `==Title==` (customizable) | `Title.` (fixed format) |
| Multilingual categories | ✅ (350+ languages) | — |
| Processing speed | Slower | ~10x faster |

### When to use wp2txt

- You need **article category information** for classification or knowledge graphs
- You want to **extract articles from specific categories** (e.g., all articles in "Japanese cities")
- You want to **extract specific articles by title** without downloading the full dump
- You want to preserve or customize section heading format
- You're building topic classifiers using categories as labels
- Processing time is not your primary constraint

### When to use WikiExtractor

- You only need plain text content (no metadata)
- Processing speed is critical
- Working with full Wikipedia dumps (20GB+)

## Responsible Data Access

**wp2txt uses official Wikipedia dump files**, which is the [recommended approach by Wikimedia Foundation](https://meta.wikimedia.org/wiki/Data_dumps) for bulk data access.

### Why dump files instead of API scraping?

The Wikimedia Foundation has expressed concerns about large-scale API scraping, particularly for AI/ML purposes:

- **Server load**: Mass API requests burden Wikipedia's infrastructure
- **Official recommendation**: Dump files are specifically provided for bulk data access
- **Terms of service**: Excessive bot requests may be blocked

wp2txt's design aligns with these guidelines:

| Approach | Server Impact | Wikimedia Stance |
|----------|---------------|------------------|
| API scraping (mass) | High | ⚠️ Discouraged |
| **Dump files (wp2txt)** | None | ✅ Recommended |

By using dump files, wp2txt enables large-scale Wikipedia data extraction while respecting Wikimedia's infrastructure and policies.

## About

WP2TXT extracts text and category data from Wikipedia dump files (encoded in XML / compressed with Bzip2), removing MediaWiki markup and other metadata.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for detailed release notes.

**January 2026 (v2.0.0)**

- **NEW: Category-based extraction** (`--from-category`) - extract all articles from a Wikipedia category
  - Supports subcategory recursion with `--depth` option
  - Preview mode with `--dry-run` to see article counts before extraction
  - Confirmation prompt with `--yes` option for automation
- **NEW: Auto-download mode** (`--lang=ja`) - automatically downloads Wikipedia dumps
- **NEW: Article extraction** (`--articles`) - extract specific articles by title
- **NEW: JSON/JSONL output format** (`--format json`) for machine-readable output
- **NEW: Content type markers** (`--markers`) - mark MATH, CODE, CHEM, TABLE, etc.
- **NEW: Streaming processing** - no intermediate XML files, reduced disk I/O
- **NEW: Cache management** - manage downloaded dumps with `--cache-status` and `--cache-clear`
- **NEW: Configuration file** (`--config-init`) - customize cache expiry, default format, etc.
- Full Ruby 4.0 compatibility
- Multilingual support for category extraction (350+ Wikipedia languages, auto-generated from MediaWiki API)
- Multilingual support for redirect detection (350+ Wikipedia languages)
- Fixed Unicode handling for emoji and supplementary plane characters
- Fixed encoding error handling (no longer crashes on invalid UTF-8)
- Improved handling of File/Image links in article output
- Performance optimizations (reduced memory allocations, regex caching)
- Comprehensive test suite (775+ tests, 78% coverage)
- Deprecated: `--convert` and `--del-interfile` options (no longer needed)

**May 2023**

- Problems caused by too many parallel processors are addressed by setting the upper limit on the number of processors to 8.

**April 2023**

- File split/delete issues fixed

**January 2023**

- Bug related to command line arguments fixed

**December 2022**

- Docker images available via Docker Hub

**November 2022**

- Code added to suppress "Invalid byte sequence error" when an ilegal UTF-8 character is input.

**August 2022**

- A new option `--category-only` has been added. When this option is enabled, only the title and category information of the article is extracted.
- A new option `--summary-only` has been added. If this option is enabled, only the title, category information, and opening paragraphs of the article will be extracted.
- Text conversion with the current version of WP2TXT is *more than 2x times faster* than the previous version due to parallel processing of multiple files (the rate of speedup depends on the CPU cores used for processing).

## Screenshot

<img src='https://raw.githubusercontent.com/yohasebe/wp2txt/master/image/screenshot.png' width="800" />

**Environment**

- WP2TXT 1.0.1
- MacBook Pro (2021 Apple M1 Pro)
- enwiki-20220720-pages-articles.xml.bz2 (19.98 GB)

In the above environment, the process (decompression, splitting, extraction, and conversion) to obtain the plain text data of the English Wikipedia takes less than 1.5 hours.

## Features

- Converts Wikipedia dump files in various languages
- **Auto-download mode** - automatically download and process dumps by language code
- **Extract specific articles** - extract individual articles by title without downloading the full dump
- **Category-based extraction** - extract all articles belonging to a Wikipedia category (with subcategory support)
- **Extracts category information of the article** (unique feature)
- **JSON/JSONL output format** for machine-readable data pipelines
- **Content type markers** - mark mathematical formulas, code blocks, chemical formulas, tables, etc.
- **Streaming processing** - processes bz2 files directly without intermediate files
- **Cache management** - downloaded dumps are cached for reuse
- **Configuration file** - customize cache expiry, default output format, and more
- Creates output files of specified size
- Allows specifying elements (page titles, section headers, paragraphs, list items) to be extracted
- Allows extracting opening paragraphs of the article

## Setting Up

### WP2TXT on Docker

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Mac/Windows/Linux)
2. Execute `docker` command in a terminal:

```shell
docker run -it -v /Users/me/localdata:/data yohasebe/wp2txt
```

- Make sure to Replace `/Users/me/localdata` with the full path to the data directory in your local computer

3. The Docker image will begin downloading and a bash prompt will appear when finished.
4. The `wp2txt` command will be avalable anywhare in the Docker container. Use the `/data` directory as the location of the input dump files and the output text files.

**IMPORTANT:**

- Configure Docker Desktop resource settings (number of cores, amount of memory, etc.) to get the best performance possible.
- When running the `wp2txt` command inside a Docker container, be sure to set the output directory to somewhere in the mounted local directory specified by the `docker run` command.

### WP2TXT on MacOS and Linux

WP2TXT requires that one of the following commands be installed on the system in order to decompress `bz2` files:

- `lbzip2` (recommended)
- `pbzip2`
- `bzip2`

In most cases, the `bzip2` command is pre-installed on the system. However, since `lbzip2` can use multiple CPU cores and is faster than `bzip2`, it is recommended that you install it additionally. WP2TXT will attempt to find the decompression command available on your system in the order listed above.

If you are using MacOS with Homebrew installed, you can install `lbzip2` with the following command:

    $ brew install lbzip2

### WP2TXT on Windows

Install [Bzip2 for Windows](http://gnuwin32.sourceforge.net/packages/bzip2.htm) and set the path so that WP2TXT can use the bunzip2.exe command. Alternatively, you can extract the Wikipedia dump file in your own way and process the resulting XML file with WP2TXT.

## Installation

### WP2TXT command

    $ gem install wp2txt

## Wikipedia Dump File

### Option 1: Auto-download (Recommended)

WP2TXT can automatically download Wikipedia dumps. Just specify the language code:

    $ wp2txt --lang=ja -o ./text

The dump will be downloaded to `~/.wp2txt/cache/` and cached for future use. You can check or clear the cache:

    $ wp2txt --cache-status           # Show cache status
    $ wp2txt --cache-clear            # Clear all cache
    $ wp2txt --cache-clear --lang=ja  # Clear cache for Japanese only

When cache is older than the configured expiry period (default: 30 days), wp2txt will display a warning but still allow you to use the cached data. Use `--update-cache` to force a fresh download:

    $ wp2txt --lang=ja --from-category="日本の都市" --update-cache -o ./cities

### Option 2: Manual Download

Download the latest Wikipedia dump file for the desired language at a URL such as

    https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles.xml.bz2

Here, `enwiki` refers to the English Wikipedia. To get the Japanese Wikipedia dump file, for instance, change this to `jawiki` (Japanese). In doing so, note that there are two instances of `enwiki` in the URL above.

Alternatively, you can also select Wikipedia dump files created on a specific date from [here](http://dumps.wikimedia.org/backup-index.html). Make sure to download a file named in the following format:

    xxwiki-yyyymmdd-pages-articles.xml.bz2

where `xx` is language code such as `en` (English)" or `ja` (japanese), and  `yyyymmdd` is the date of creation (e.g. `20220801`).

## Basic Usage

### Auto-download and process (Recommended)

    $ wp2txt --lang=ja -o ./text

This automatically downloads the Japanese Wikipedia dump and extracts plain text.

### Extract specific articles by title

    $ wp2txt --lang=ja --articles="認知言語学,生成文法" -o ./articles

This extracts only the specified articles. Only the index file and necessary data streams are downloaded, making it much faster than processing the full dump.

### Extract articles from a category

    $ wp2txt --lang=ja --from-category="日本の都市" -o ./cities

This extracts all articles belonging to the specified Wikipedia category. You can include subcategories with `--depth`:

    $ wp2txt --lang=ja --from-category="日本の都市" --depth=2 -o ./cities

Preview the category without downloading (shows article counts):

    $ wp2txt --lang=ja --from-category="日本の都市" --dry-run

Skip confirmation prompt for automation:

    $ wp2txt --lang=ja --from-category="日本の都市" --yes -o ./cities

### Extract plain text from local dump file

    $ wp2txt -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./text

This will stream the compressed dump file directly, extracting plain text without creating intermediate files.

### Extract only category info

    $ wp2txt -g -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./category

### Extract opening paragraphs (summary)

    $ wp2txt -s -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./summary

### Output as JSON/JSONL

    $ wp2txt --format json -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./json

## Sample Output

Output contains title, category info, paragraphs

    $ wp2txt -i ./input -o /output

- [English Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en.txt)
- [Japanese Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja.txt)

Output containing title and category only

    $ wp2txt -g -i ./input -o /output

- [English Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en_category.txt)
- [Japanese Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja_category.txt)

Output containing title, category, and summary

    $ wp2txt -s -i ./input -o /output

- [English Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en_summary.txt)
- [Japanese Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja_summary.txt)

### JSON/JSONL Output (v2.0+)

Output in JSONL format (one JSON object per line):

    $ wp2txt --format json -i ./input -o /output

Each line contains:

```json
{"title": "Article Title", "categories": ["Cat1", "Cat2"], "text": "...", "redirect": null}
```

For redirect articles:

```json
{"title": "NYC", "categories": [], "text": "", "redirect": "New York City"}
```

### Content Type Markers (v2.0+)

By default, special content is replaced with marker placeholders to indicate content type:

**Inline markers** (appear within sentences):

| Marker | Content Type | Example MediaWiki |
|--------|--------------|-------------------|
| `[MATH]` | Mathematical formulas | `<math>E=mc^2</math>` |
| `[CODE]` | Inline code | `<code>variable</code>` |
| `[CHEM]` | Chemical formulas | `<chem>H2O</chem>` |
| `[IPA]` | IPA phonetic notation | `{{IPA|...}}` |

**Block markers** (standalone content):

| Marker | Content Type | Example MediaWiki |
|--------|--------------|-------------------|
| `[CODEBLOCK]` | Source code blocks | `<syntaxhighlight>`, `<source>`, `<pre>` |
| `[TABLE]` | Wiki tables | `{| ... |}` |
| `[SCORE]` | Musical scores | `<score>...</score>` |
| `[TIMELINE]` | Timeline graphics | `<timeline>...</timeline>` |
| `[GRAPH]` | Graphs/charts | `<graph>...</graph>` |
| `[INFOBOX]` | Information boxes | `{{Infobox ...}}` |
| `[NAVBOX]` | Navigation boxes | `{{Navbox ...}}` |
| `[GALLERY]` | Image galleries | `<gallery>...</gallery>` |
| `[SIDEBAR]` | Sidebar templates | `{{Sidebar ...}}` |
| `[MAPFRAME]` | Interactive maps | `<mapframe>...</mapframe>` |
| `[IMAGEMAP]` | Clickable image maps | `<imagemap>...</imagemap>` |
| `[REFERENCES]` | Reference lists | `{{reflist}}`, `{{refbegin}}...{{refend}}` |

Configure markers with `--markers`:

    $ wp2txt --lang=en --markers=all -o ./text        # All markers (default)
    $ wp2txt --lang=en --markers=math,code -o ./text  # Only MATH and CODE markers

**Note**: The `--markers=none` option is deprecated. Complete removal of special content can make surrounding text nonsensical (e.g., "Einstein discovered ." instead of "Einstein discovered [MATH].").

### Citation Extraction (v2.0+)

By default, citation templates like `{{cite book}}` are removed. Use `--extract-citations` to extract formatted citations instead:

    $ wp2txt --lang=en --extract-citations -o ./text

When using the Ruby API, you can also enable this with the `extract_citations` option:

```ruby
require 'wp2txt'
include Wp2txt

# Default: citations are removed
text = "{{cite book |last=Smith |title=The Book |year=2020}}"
format_wiki(text)
# => ""

# With extract_citations: true
format_wiki(text, extract_citations: true)
# => "Smith. \"The Book\". 2020."

# Works with refbegin/refend blocks
bibliography = "{{refbegin}}\n* {{cite book |last=Author |title=Book |year=2021}}\n{{refend}}"
format_wiki(bibliography, extract_citations: true)
# => "* Author. \"Book\". 2021."
```

Supported citation templates:
- `{{cite book}}`, `{{cite web}}`, `{{cite news}}`, `{{cite journal}}`
- `{{cite magazine}}`, `{{cite conference}}`, `{{Citation}}`

## Command Line Options

Command line options are as follows:

    Usage: wp2txt [options]

    Input source (one of --input or --lang required):
      -i, --input=<s>                  Path to compressed file (bz2) or XML file
      -L, --lang=<s>                   Wikipedia language code (e.g., ja, en, de) for auto-download
      -A, --articles=<s>               Specific article titles to extract (comma-separated, requires --lang)
      -G, --from-category=<s>          Extract articles from Wikipedia category (requires --lang)
      -D, --depth=<i>                  Subcategory recursion depth for --from-category (default: 0)
      -y, --yes                        Skip confirmation prompt for category extraction
      --dry-run                        Preview category extraction without downloading

    Output options:
      -o, --output-dir=<s>             Path to output directory (default: current directory)
      -j, --format=<s>                 Output format: text or json (JSONL) (default: text)

    Cache management:
      --cache-dir=<s>                  Cache directory for downloaded dumps (default: ~/.wp2txt/cache)
      --cache-status                   Show cache status and exit
      --cache-clear                    Clear cache and exit (use with --lang to clear specific language)
      -U, --update-cache               Force refresh of cached dump files (ignore staleness)

    Configuration:
      --config-init                    Create default configuration file (~/.wp2txt/config.yml)
      --config-path=<s>                Path to configuration file

    Processing options:
      -a, --category, --no-category    Show article category information (default: true)
      -g, --category-only              Extract only article title and categories
      -s, --summary-only               Extract only article title, categories, and summary text before first heading
      -f, --file-size=<i>              Approximate size (in MB) of each output file (0 for single file) (default: 10)
      -n, --num-procs                  Number of processes (up to 8) to be run concurrently (default: max num of available CPU cores minus two)
      -t, --title, --no-title          Keep page titles in output (default: true)
      -d, --heading, --no-heading      Keep section titles in output (default: true)
      -l, --list                       Keep unprocessed list items in output
      -r, --ref                        Keep reference notations in the format [ref]...[/ref]
      -e, --redirect                   Show redirect destination
      -m, --marker, --no-marker        Show symbols prefixed to list items, definitions, etc. (default: true)
      -k, --markers=<s>                Content type markers: math,code,chem,table,score,timeline,graph,ipa or 'all' (default: all)
      -C, --extract-citations          Extract formatted citations instead of removing them
      -b, --bz2-gem                    Use Ruby's bzip2-ruby gem instead of a system command
      -v, --version                    Print version and exit
      -h, --help                       Show this message

## Configuration File

wp2txt supports a YAML configuration file for persistent settings. Create the default configuration:

    $ wp2txt --config-init

This creates `~/.wp2txt/config.yml`:

```yaml
cache:
  # Days before dump files are considered stale (1-365)
  dump_expiry_days: 30
  # Days before category cache expires (1-90)
  category_expiry_days: 7
  # Cache directory
  directory: ~/.wp2txt/cache

defaults:
  # Default output format: text or json
  format: text
  # Default subcategory recursion depth (0-10)
  depth: 0
```

Command-line options override configuration file settings.

## Caveats

* Special content like mathematical formulas, code blocks, and chemical formulas are marked with placeholders (e.g., `[MATH]`, `[CODE]`, `[CHEM]`) by default. Use `--markers=math,code` to show only specific markers.
* Some text data may not be extracted correctly for various reasons (incorrect matching of begin/end tags, language-specific formatting rules, etc.).
* The conversion process can take longer than expected. When dealing with a huge data set such as the English Wikipedia on a low-spec environment, it can take several hours or more.

## Useful Links

* [Wikipedia Database backup dumps](http://dumps.wikimedia.org/backup-index.html)

## Author

* Yoichiro Hasebe (<yohasebe@gmail.com>)

## References

The author will appreciate your mentioning one of these in your research.

* Yoichiro HASEBE. 2006. [Method for using Wikipedia as Japanese corpus.](http://ci.nii.ac.jp/naid/110006226727) _Doshisha Studies in Language and Culture_ 9(2), 373-403.
* 長谷部陽一郎. 2006. [Wikipedia日本語版をコーパスとして用いた言語研究の手法](http://ci.nii.ac.jp/naid/110006226727). 『言語文化』9(2), 373-403.

Or use this BibTeX entry:

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
