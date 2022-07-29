# WP2TXT

Wikipedia dump file to text converter

**IMPORTANT:** This is a project still work in progress and it could be slow, unstable, and even destructive! It should be used with caution.

## About

WP2TXT extracts plain text data from Wikipedia dump file (encoded in XML/compressed with Bzip2) stripping all the MediaWiki markups and other metadata. It is originally intended to be useful for researchers who look for an easy way to obtain open-source multi-lingual corpora, but may be handy for other purposes.

**UPDATE (July 2022)**: Version 0.9.3 has added a new option `category_only`. With this option enabled, wp2txt extracts article title and category info only. Please see output examples below.

## Features

* Convert dump files of Wikipedia of various languages
* Create output files of specified size.
* Allow users to specify text elements to be extracted/converted (page titles, section titles, lists, and tables)
* Extract category information of each article

## Installation
    
    $ gem install wp2txt

## Usage

Obtain a Wikipedia dump file (from [here](http://dumps.wikimedia.org/backup-index.html)) with a file name such as:

    xxwiki-yyyymmdd-pages-articles.xml.bz2

where `xx` is language code such as "en (English)" or "", and  `yyyymmdd` is the date of creation (e.g. 20220720).

### Example 1

The following extracts text data, including list items and excluding tables.

    $ wp2txt -i xxwiki-yyyymmdd-pages-articles.xml.bz2 -o /output_dir

- [Output example (English)](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en.txt)
- [Output example (Japanese)](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja.txt)

### Example 2

The following will extract only article titles and the categories to which each article belongs:

    $ wp2txt -y -i xxwiki-yyyymmdd-pages-articles.xml.bz2 -o /output_dir

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

* Certain types of data such as mathematical equations and computer source code are not be properly converted.  Please remember this software is originally intended for correcting “sentences” for linguistic studies.
* Extraction of normal text data could sometimes fail for various reasons (e.g. illegal matching of begin/end tags, language-specific conventions of formatting, etc). 
* Conversion process can take far more than you would expect. It could take several hours or more when dealing with a huge data set such as the English Wikipedia on a low-spec environments.
* Because of nature of the task, WP2TXT needs much machine power and consumes a lot of memory/storage resources. The process thus could halt unexpectedly. It may even get stuck, in the worst case, without getting gracefully terminated. Please understand this and use the software __at your own risk__.

### Useful Links

* [Wikipedia Database backup dumps](http://dumps.wikimedia.org/backup-index.html)
                
### Author

* Yoichiro Hasebe (<yohasebe@gmail.com>)

### References

The author will appreciate your mentioning one of these in your research.

* Yoichiro HASEBE. 2006. [Method for using Wikipedia as Japanese corpus.](http://ci.nii.ac.jp/naid/110006226727) _Doshisha Studies in Language and Culture_ 9(2), 373-403.
* 長谷部陽一郎. 2006. [Wikipedia日本語版をコーパスとして用いた言語研究の手法](http://ci.nii.ac.jp/naid/110006226727). 『言語文化』9(2), 373-403.

### License

This software is distributed under the MIT License. Please see the LICENSE file.
