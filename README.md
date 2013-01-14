# WP2TXT

Wikipedia dump file to text converter

### About ###

WP2TXT extracts plain text data from Wikipedia dump file (encoded in XML/compressed with Bzip2) stripping all the MediaWiki markups and other metadata. It is originally intended to be useful for researchers who look for an easy way to obtain open-source multi-lingual corpora, but may be handy for other purposes.

### Features ###

* Convert dump files of Wikipedia of multiple languages (I hope).
* Create output files of specified size.
* Allow users to specify text elements to be extracted/converted (page titles, section titles, lists, and tables).

WP2TXT before version 0.4.0 came with Mac/Windows GUI. Now it's become a pure command-line application--Sorry GUI folks, but there seems more demand for an easy-to-hack CUI package than a not-very-flexible GUI app.

### Installation
    
    $ gem install bundler
    $ bundle install
    
    $ gem install wp2txt

### Usage

Obtain a Wikipedia dump file (see the link below) with a file name such as:

    xxwiki-yyyymmdd-pages-articles.xml.bz2

where `xx` is language code such as "en (English)" or "ja (Japanese)", and  `yyyymmdd` is the date of creation (e.g. 20120601).

Command line options are as follows:

    Usage: wp2txt [options]
    where [options] are:
          --input-file, -i:   Wikipedia dump file with .bz2 (compressed) or .txt (uncompressed) format
      --output-dir, -o <s>:   Output directory (default: current directory)
         --convert-off, -c:   Output XML (without converting to plain text)
            --list-off, -l:   Exclude list items from output
         --heading-off, -d:   Exclude section titles from output
           --title-off, -t:   Exclude page titles from output
           --table-off, -a:   Exclude page titles from output (default: true)
        --template-off, -e:   Remove multi-line template notations from output
        --strip-marker, -s:   Remove symbols prefixed to list items, definitions, etc.
       --file-size, -f <i>:   Approximate size (in MB) of each output file (default: 10)
             --version, -v:   Print version and exit
                --help, -h:   Show this message

### Limitations ###

* Certain types of data such as mathematical equations and computer source code are not be properly converted.  Please remember this software is originally intended for correcting “sentences” for linguistic studies.
* Extraction of normal text data could sometimes fail for various reasons (e.g. illegal matching of begin/end tags, language-specific conventions of formatting, etc). 
* Conversion process can take far more than you would expect. It could take several hours or more when dealing with a huge data set such as the English Wikipedia on a low-spec environments.
* Because of nature of the task, WP2TXT needs much machine power and consumes a lot of memory/storage resources. The process thus could halt unexpectedly. It may even get stuck, in the worst case, without getting gracefully terminated. Please understand this and use the software __at your own risk__.

### Useful Link ###

* [Wikipedia Database backup dumps](http://dumps.wikimedia.org/backup-index.html)
                
### Author ###

* Yoichiro Hasebe (<yohasebe@gmail.com>)

### License ###

This software is distributed under the MIT License. Please see the LICENSE file.
