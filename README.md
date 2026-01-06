<img src='https://raw.githubusercontent.com/yohasebe/wp2txt/master/image/wp2txt-logo.svg' width="400" />

A command-line toolkit to extract text content and category data from Wikipedia dump files

## Why wp2txt?

There are several tools for extracting plain text from Wikipedia dumps. [WikiExtractor](https://github.com/attardi/wikiextractor) is a popular Python-based tool known for its speed. However, **wp2txt offers unique features that WikiExtractor does not provide**:

| Feature | wp2txt | WikiExtractor |
|---------|--------|---------------|
| Plain text extraction | ✅ | ✅ |
| **Category metadata extraction** | ✅ | ❌ |
| Category-only output (`-g`) | ✅ | ❌ |
| Section headings | `==Title==` (customizable) | `Title.` (fixed format) |
| Multilingual categories | ✅ (30+ languages) | — |
| Processing speed | Slower | ~10x faster |

### When to use wp2txt

- You need **article category information** for classification or knowledge graphs
- You want to preserve or customize section heading format
- You're building topic classifiers using categories as labels
- Processing time is not your primary constraint

### When to use WikiExtractor

- You only need plain text content (no metadata)
- Processing speed is critical
- Working with full Wikipedia dumps (20GB+)

## About

WP2TXT extracts text and category data from Wikipedia dump files (encoded in XML / compressed with Bzip2), removing MediaWiki markup and other metadata.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for detailed release notes.

**January 2026 (v2.0.0)**

- **NEW: JSON/JSONL output format** (`--format json`) for machine-readable output
- **NEW: Streaming processing** - no intermediate XML files, reduced disk I/O
- Full Ruby 4.0 compatibility
- Multilingual support for category extraction (30+ languages including Japanese, Chinese, German, French, Russian, etc.)
- Multilingual support for redirect detection (25+ languages)
- Fixed Unicode handling for emoji and supplementary plane characters
- Fixed encoding error handling (no longer crashes on invalid UTF-8)
- Improved handling of File/Image links in article output
- Performance optimizations (reduced memory allocations, regex caching)
- Comprehensive test suite (252 tests, 83%+ coverage)
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
- **Extracts category information of the article** (unique feature)
- **JSON/JSONL output format** for machine-readable data pipelines
- **Streaming processing** - processes bz2 files directly without intermediate files
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

Download the latest Wikipedia dump file for the desired language at a URL such as

    https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles.xml.bz2

Here, `enwiki` refers to the English Wikipedia. To get the Japanese Wikipedia dump file, for instance, change this to `jawiki` (Japanese). In doing so, note that there are two instances of `enwiki` in the URL above.

Alternatively, you can also select Wikipedia dump files created on a specific date from [here](http://dumps.wikimedia.org/backup-index.html). Make sure to download a file named in the following format:

    xxwiki-yyyymmdd-pages-articles.xml.bz2

where `xx` is language code such as `en` (English)" or `ja` (japanese), and  `yyyymmdd` is the date of creation (e.g. `20220801`).

## Basic Usage

### Extract plain text from Wikipedia dump

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

## Command Line Options

Command line options are as follows:

    Usage: wp2txt [options]
    where [options] are:
      -i, --input                      Path to compressed file (bz2) or XML file, or path to directory containing XML files
      -o, --output-dir=<s>             Path to output directory
      -j, --format=<s>                 Output format: text or json (JSONL) (default: text)
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
      -b, --bz2-gem                    Use Ruby's bzip2-ruby gem instead of a system command
      -v, --version                    Print version and exit
      -h, --help                       Show this message

## Caveats

* Some data, such as mathematical formulas and computer source code, will not be converted correctly.
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
