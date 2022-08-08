<img src='./image/wp2txt-logo.svg' width="400" />

Text conversion tool to extract content and category data from Wikipedia dump files

## About

WP2TXT extracts plain text data from Wikipedia dump files (encoded in XML / compressed with Bzip2), removing all MediaWiki markup and other metadata. It was developed for researchers who want easy access to open source multilingual corpora, but can be used for other purposes as well.

**UPDATE (August 2022)**

1. A new option `--category-only` has been added. When this option is enabled, only the title and category information of the article is extracted.
2. A new option `--summary-only` has been added. If this option is enabled, only the title and text data from the first paragraph of the article (= summary) will be extracted.
3. The current WP2TXT is *several times faster* than the previous version due to parallel processing of multiple files (the rate of speedup depends on the CPU cores used for processing).

## Features

- Converts Wikipedia dump files in various languages
- Creates output files of specified size
- Allows specifying ext elements (page titles, section headers, paragraphs, list items) to be extracted
- Allows extracting category information of the article
- Allows extracting summary text of the article

## Installation

    $ gem install wp2txt

## Preparation

First, you will need to obtain a Wikipedia dump file (from [here](http://dumps.wikimedia.org/backup-index.html)) with a file name like this:

    xxwiki-yyyymmdd-pages-articles.xml.bz2

where `xx` is language code such as "en (English)" or "ja (Japanese)", and  `yyyymmdd` is the date of creation (e.g. 20220720).

Alternatively, you can download multiple smaller files with file names such as:

    enwiki-yyyymmdd-pages-articles1-xxxxxxxx.xml.bz2
    enwiki-yyyymmdd-pages-articles2-xxxxxxxx.xml.bz2
    enwiki-yyyymmdd-pages-articles3-xxxxxxxx.xml.bz2

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

It is possible (though not recommended) to 1) decompress the dump files, 2) split the data into files, and 3) extract the text from them with just one line of command.

    $ wp2txt -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./text

## Sample Input and Output

Output contains title, category info, paragraphs

- [English](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en.txt)
- [Japanese](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja.txt)

Output containing title and category info only

- [English](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en_category.txt)
- [Japanese](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja_category.txt)

Output containing title, category, and summary

- [English](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en_summary.txt)
- [Japanese](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja_summary.txt)

## Command Line Options

Command line options are as follows:

    Usage: wp2txt [options]
    where [options] are:
      -i, --input                      Path to compressed file (bz2) or uncompressed file (xml), or path to directory containing files of the latter format
      -o, --output-dir=<s>             Path to output directory
      -c, --convert, --no-convert      Output in plain text (converting from XML) (default: true)
      -a, --category, --no-category    Show article category information (default: true)
      -g, --category-only              Extract only article title and categories
      -s, --summary-only               Extract only article title, categories, and summary text before first heading
      -f, --file-size=<i>              Approximate size (in MB) of each output file (default: 10)
      -n, --num-procs                  Number of proccesses to be run concurrently (default: max num of CPU cores minus two)
      -x, --del-interfile              Delete intermediate XML files from output dir
      -t, --title, --no-title          Keep page titles in output (default: true)
      -d, --heading, --no-heading      Keep section titles in output (default: true)
      -l, --list                       Keep unprocessed list items in output
      -r, --ref                        Keep reference notations in the format [ref]...[/ref]
      -e, --redirect                   Show redirect destination
      -m, --marker, --no-marker        Show symbols prefixed to list items, definitions, etc. (Default: true)
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

## License

This software is distributed under the MIT License. Please see the LICENSE file.
