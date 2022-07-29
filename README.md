# WP2TXT

Wikipedia dump file to text converter that extracts both content and category data

## About

WP2TXT extracts plain text data from a Wikipedia dump file (encoded in XML / compressed with Bzip2), removing all MediaWiki markup and other metadata. It was developed for researchers who want easy access to open-source multilingual corpora, but may be used for other purposes as well.

**UPDATE (July 2022)**: Version 0.9.3 adds a new option `category_only`. When this option is enabled, wp2txt will extract only the title and category information of the article. See output examples below.


## Features

* Converts Wikipedia dump files in various languages
* Creates output files of specified size
* Can specify text elements to be extracted and converted (page titles, section titles, lists, tables)
* Can extract category information for each article


## Installation

    $ gem install wp2txt

## Usage

Obtain a Wikipedia dump file (from [here](http://dumps.wikimedia.org/backup-index.html)) with a file name such as:

> `xxwiki-yyyymmdd-pages-articles.xml.bz2`

where `xx` is language code such as "en (English)" or "ja (Japanese)", and  `yyyymmdd` is the date of creation (e.g. 20220720).

### Example 1 (basic)

The following extracts text data, including list items and excluding tables.

    $ wp2txt -i xxwiki-yyyymmdd-pages-articles.xml.bz2 -o /output_dir

- [Output example (English)](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en.txt)
- [Output example (Japanese)](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja.txt)

### Example 2 (title and category information only)

The following will extract only article titles and the categories to which each article belongs:

    $ wp2txt --category-only -i xxwiki-yyyymmdd-pages-articles.xml.bz2 -o /output_dir

Each line of the output data contains the title and the categories of an article:

> title `TAB` category1`,` category2`,` category3`,` ... 

- [Output example (English)](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en_categories.txt)
- [Output example (Japanese)](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja_categories.txt)

## Options

Command line options are as follows:

    Usage: wp2txt [options]
    where [options] are:
               --input-file, -i:   Wikipedia dump file with .bz2 (compressed) or
                                   .txt (uncompressed) format
           --output-dir, -o <s>:   Output directory (default: current directory)
    --convert, --no-convert, -c:   Output in plain text (converting from XML)
                                   (default: true)
          --list, --no-list, -l:   Show list items in output (default: true)
    --heading, --no-heading, -d:   Show section titles in output (default: true)
        --title, --no-title, -t:   Show page titles in output (default: true)
                    --table, -a:   Show table source code in output (default: false)
                   --inline, -n:   leave inline template notations unmodified (default: false)
                --multiline, -m:   leave multiline template notations unmodified (default: false)
                      --ref, -r:   leave reference notations in the format (default: false)
                                   [ref]...[/ref]
                 --redirect, -e:   Show redirect destination (default: false)
      --marker, --no-marker, -k:   Show symbols prefixed to list items,
                                   definitions, etc. (Default: true)
                 --category, -g:   Show article category information (default: true)
            --category-only, -y:   Extract only article title and categories (default: false)
            --file-size, -f <i>:   Approximate size (in MB) of each output file
                                   (default: 10)
          -u, --num-threads=<i>:   Number of threads to be spawned (capped to the number of CPU cores;
                                   set 99 to spawn max num of threads) (default: 4)
                  --version, -v:   Print version and exit
                     --help, -h:   Show this message

## Caveats

* Some data, such as mathematical formulas and computer source code, will not be converted correctly. 
* Some text data may not be extracted correctly for various reasons (incorrect matching of begin/end tags, language-specific formatting rules, etc.).
* The conversion process can take longer than expected. When dealing with a huge data set such as the English Wikipedia on a low-spec environment, it can take several hours or more.
* WP2TXT, by the nature of its task, requires a lot of machine power and consumes a large amount of memory/storage resources. Therefore, there is a possibility that the process may stop unexpectedly. In the worst case, the process may even freeze without terminating successfully. Please understand this and use at your own risk. 

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
