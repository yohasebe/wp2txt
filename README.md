<img src='https://raw.githubusercontent.com/yohasebe/wp2txt/master/image/wp2txt-logo.svg' width="400" />

Text conversion tool to extract content and category data from Wikipedia dump files

## About

WP2TXT extracts plain text data from Wikipedia dump files (encoded in XML / compressed with Bzip2), removing all MediaWiki markup and other metadata.

**UPDATE (August 2022)**

1. A new option `--category-only` has been added. When this option is enabled, only the title and category information of the article is extracted.
2. A new option `--summary-only` has been added. If this option is enabled, only the title and text data from the opening paragraphs of the article (= summary) will be extracted.
3. The current WP2TXT is *several times faster* than the previous version due to parallel processing of multiple files (the rate of speedup depends on the CPU cores used for processing).

## Screenshot

<img src='https://raw.githubusercontent.com/yohasebe/wp2txt/master/image/screenshot.png' width="700" />

- WP2TXT 1.0.0
- MacBook Pro (2019) 2.3GHz 8Core Intel Core i9
- enwiki-20220802-pages-articles.xml.bz2 (approx. 20GB)

In the above environment, the process (decompression, splitting, extraction, and conversion) to obtain the plain text data of the English Wikipedia takes a little over two hours.

## Features

- Converts Wikipedia dump files in various languages
- Creates output files of specified size
- Allows specifying ext elements (page titles, section headers, paragraphs, list items) to be extracted
- Allows extracting category information of the article
- Allows extracting opening paragraphs of the article

## Installation

    $ gem install wp2txt

## Preparation

First, download the latest Wikipedia dump file for the language of your choice.

    https://dumps.wikimedia.org/xxwiki/latest/xxwiki-latest-pages-articles.xml.bz2

where `xx` is language code such as `en` (English) or `zh` (Chinese). Change it to `ja`, for instance, if you want the latest Japanese Wikipedia dump file.

Alternatively, you can also select Wikipedia dump files created on a specific date from [here](http://dumps.wikimedia.org/backup-index.html). Make sure to download a file named in the following format:

    xxwiki-yyyymmdd-pages-articles.xml.bz2

where `xx` is language code such as `en` (English)" or `ko` (Korean), and  `yyyymmdd` is the date of creation (e.g. `20220801`).

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
