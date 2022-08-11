<img src='https://raw.githubusercontent.com/yohasebe/wp2txt/master/image/wp2txt-logo.svg' width="400" />

A command-line toolkit to extract text content and category data from Wikipedia dump files

## About

WP2TXT extracts text and category data from Wikipedia dump files (encoded in XML / compressed with Bzip2), removing MediaWiki markup and other metadata.

**UPDATE (August 2022)**

1. A new option `--category-only` has been added. When this option is enabled, only the title and category information of the article is extracted.
2. A new option `--summary-only` has been added. If this option is enabled, only the title, category information, and opening paragraphs of the article will be extracted.
3. Text conversion with the current version of WP2TXT is *more than 2x times faster* than the previous version due to parallel processing of multiple files (the rate of speedup depends on the CPU cores used for processing).

## Screenshot

<img src='https://raw.githubusercontent.com/yohasebe/wp2txt/master/image/screenshot.png' width="700" />

**Environment** 

- WP2TXT 1.0.1
- MacBook Pro (2021 Apple M1 Pro) 
- enwiki-20220720-pages-articles.xml.bz2 (19.98 GB)

In the above environment, the process (decompression, splitting, extraction, and conversion) to obtain the plain text data of the English Wikipedia takes less than 1.5 hours.

## Features

- Converts Wikipedia dump files in various languages
- Creates output files of specified size
- Allows specifying ext elements (page titles, section headers, paragraphs, list items) to be extracted
- Allows extracting category information of the article
- Allows extracting opening paragraphs of the article

## Preparation

### For MacOS / Linux/ WSL2

WP2TXT requires that one of the following commands be installed on the system in order to decompress `bz2` files:

- `lbzip2` (recommended)
- `pbzip2`
- `bzip2`

In most cases, the `bzip2` command is pre-installed on the system. However, since `lbzip2` can use multiple CPU cores and is faster than `bzip2`, it is recommended that you install it additionally. WP2TXT will attempt to find the decompression command available on your system in the order listed above.

If you are using MacOS with Homebrew installed, you can install `lbzip2` with the following command:

    $ brew install lbzip2

### For Windows

Install [Bzip2 for Windows](http://gnuwin32.sourceforge.net/packages/bzip2.htm) and set the path so that WP2TXT can use the bunzip2.exe command. Alternatively, you can extract the Wikipedia dump file in your own way and process the resulting XML file with WP2TXT.

## Installation

### WP2TXT command

    $ gem install wp2txt

## Wikipedia Dump File

Download the latest Wikipedia dump file for the desired language at a URL such as

    https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles.xml.bz2

Here, `enwiki` refers to the English Wikipedia. To get the Japanese Wikipedia dump file, for instance, change this to jawiki (Japanese). In doing so, note that there are two instances of `enwiki` in the URL above.

Alternatively, you can also select Wikipedia dump files created on a specific date from [here](http://dumps.wikimedia.org/backup-index.html). Make sure to download a file named in the following format:

    xxwiki-yyyymmdd-pages-articles.xml.bz2

where `xx` is language code such as `en` (English)" or `ja` (japanese), and  `yyyymmdd` is the date of creation (e.g. `20220801`).

## Basic Usage

Suppose you have a folder with a wikipedia dump file and empty subfolders organized as follows:

```
.
├── enwiki-20220801-pages-articles.xml.bz2
├── /xml
├── /text
├── /category
└── /summary
```

### Decompress and Split

The following command will decompress the entire wikipedia data and split it into many small (approximately 10 MB) XML files.

    $ wp2txt --no-convert -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./xml

**Note**: The resulting files are not well-formed XML. They contain part of the orignal XML extracted from the Wikipedia dump file, taking care to ensure that the content within the <page> tag is not split into multiple files.

### Extract plain text from MediaWiki XML

    $ wp2txt -i ./xml -o ./text


### Extract only category info from MediaWiki XML

    $ wp2txt -g -i ./xml -o ./category

### Extract opening paragraphs from MediaWiki XML

    $ wp2txt -s -i ./xml -o ./summary

### Extract directly from bz2 compressed file

It is possible (though not recommended) to 1) decompress the dump files, 2) split the data into files, and 3) extract the text just one line of command. You can automatically remove all the intermediate XML files with `-x` option.

    $ wp2txt -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./text -x

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

## Command Line Options

Command line options are as follows:

    Usage: wp2txt [options]
    where [options] are:
      -i, --input                      Path to compressed file (bz2) or decompressed file (xml), or path to directory containing files of the latter format
      -o, --output-dir=<s>             Path to output directory
      -c, --convert, --no-convert      Output in plain text (converting from XML) (default: true)
      -a, --category, --no-category    Show article category information (default: true)
      -g, --category-only              Extract only article title and categories
      -s, --summary-only               Extract only article title, categories, and summary text before first heading
      -f, --file-size=<i>              Approximate size (in MB) of each output file (default: 10)
      -n, --num-procs                  Number of proccesses to be run concurrently (default: max num of available CPU cores minus two)
      -x, --del-interfile              Delete intermediate XML files from output dir
      -t, --title, --no-title          Keep page titles in output (default: true)
      -d, --heading, --no-heading      Keep section titles in output (default: true)
      -l, --list                       Keep unprocessed list items in output
      -r, --ref                        Keep reference notations in the format [ref]...[/ref]
      -e, --redirect                   Show redirect destination
      -m, --marker, --no-marker        Show symbols prefixed to list items, definitions, etc. (Default: true)
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
@misc{WP2TXT_2022,
  author = {Yoichiro Hasebe},
  title = {WP2TXT: A command-line toolkit to extract text content and category data from Wikipedia dump files},
  url = {https://github.com/yohasebe/wp2txt}
  year = {2022},
}
```

## License

This software is distributed under the MIT License. Please see the LICENSE file.
