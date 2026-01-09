<img src='https://raw.githubusercontent.com/yohasebe/wp2txt/master/image/wp2txt-logo.svg' width="400" />

Wikipediaダンプファイルからテキストコンテンツとカテゴリデータを抽出するコマンドラインツールキット

[English](README.md) | 日本語

## 概要

WP2TXTはWikipediaダンプファイルからプレーンテキストとカテゴリ情報を抽出します。XMLダンプ（bzip2圧縮）を処理し、MediaWikiマークアップを除去して、コーパス言語学やテキストマイニングなどの研究に適したクリーンなテキストを出力します。

## 主な機能

- **カテゴリメタデータ抽出** - 記事のカテゴリ情報を出力に保持
- **カテゴリベース抽出** - 特定のWikipediaカテゴリから全記事を抽出
- **タイトル指定抽出** - フルダンプをダウンロードせずに特定記事を抽出
- **自動ダウンロード** - 言語コード指定でダンプを自動ダウンロード
- **多言語対応** - 350以上のWikipedia言語でカテゴリ・リダイレクトを検出
- **ストリーミング処理** - 中間ファイルなしで大規模ダンプを処理
- **JSON出力** - データパイプライン向けの機械可読JSONL形式

## ユースケース

wp2txtは以下の用途に適しています：

- カテゴリ情報を活用した分野別コーパスの構築
- トピック領域を横断した比較言語研究
- NLPタスク向けのメタデータ付きWikipediaテキスト抽出
- 並行カテゴリ構造を利用した対照言語研究

## データアクセス

wp2txtは[公式Wikipediaダンプファイル](https://meta.wikimedia.org/wiki/Data_dumps)を使用します。これはバルクデータアクセスの推奨方法であり、Wikimediaのインフラガイドラインに準拠しています。

## 変更履歴

詳細なリリースノートは[CHANGELOG.md](CHANGELOG.md)を参照してください。

**2026年1月 (v2.0.0)**

- **新機能: カテゴリベース抽出** (`--from-category`) - Wikipediaカテゴリから全記事を抽出
  - `--depth`オプションでサブカテゴリの再帰をサポート
  - `--dry-run`でダウンロード前に記事数をプレビュー
  - `--yes`オプションで自動化用に確認プロンプトをスキップ
- **新機能: 自動ダウンロードモード** (`--lang=ja`) - Wikipediaダンプを自動ダウンロード
- **新機能: 記事抽出** (`--articles`) - タイトル指定で特定記事を抽出
- **新機能: JSON/JSONL出力形式** (`--format json`) - 機械可読出力
- **新機能: コンテンツタイプマーカー** (`--markers`) - MATH, CODE, CHEM, TABLEなどをマーク
- **新機能: ストリーミング処理** - 中間XMLファイルなし、ディスクI/O削減
- **新機能: キャッシュ管理** - `--cache-status`と`--cache-clear`でダウンロード済みダンプを管理
- **新機能: 設定ファイル** (`--config-init`) - キャッシュ有効期限、デフォルト形式などをカスタマイズ
- Ruby 4.0完全対応
- カテゴリ抽出の多言語対応（350以上のWikipedia言語、MediaWiki APIから自動生成）
- リダイレクト検出の多言語対応（350以上のWikipedia言語）
- 絵文字と補助面文字のUnicode処理を修正
- エンコーディングエラー処理を修正（無効なUTF-8でクラッシュしなくなった）
- 記事出力でのFile/Imageリンク処理を改善
- パフォーマンス最適化（メモリ割り当て削減、正規表現キャッシュ）
- 包括的なテストスイート（775以上のテスト、78%カバレッジ）
- 非推奨: `--convert`と`--del-interfile`オプション（不要になった）

## 機能

- 各言語のWikipediaダンプファイルを変換
- **自動ダウンロードモード** - 言語コードでダンプを自動ダウンロード・処理
- **特定記事の抽出** - フルダンプをダウンロードせずにタイトルで個別記事を抽出
- **カテゴリベース抽出** - Wikipediaカテゴリに属する全記事を抽出（サブカテゴリ対応）
- **記事のカテゴリ情報を抽出**（独自機能）
- **JSON/JSONL出力形式** - 機械可読データパイプライン向け
- **コンテンツタイプマーカー** - 数式、コードブロック、化学式、表などをマーク
- **ストリーミング処理** - 中間ファイルなしでbz2ファイルを直接処理
- **キャッシュ管理** - ダウンロードしたダンプを再利用のためにキャッシュ
- **設定ファイル** - キャッシュ有効期限、デフォルト出力形式などをカスタマイズ
- 指定サイズの出力ファイルを作成
- 抽出する要素（ページタイトル、セクション見出し、段落、リスト項目）を指定可能
- 記事の冒頭段落を抽出可能

## セットアップ

### Docker上のWP2TXT

1. [Docker Desktop](https://www.docker.com/products/docker-desktop/)をインストール（Mac/Windows/Linux）
2. ターミナルで`docker`コマンドを実行：

```shell
docker run -it -v /Users/me/localdata:/data yohasebe/wp2txt
```

- `/Users/me/localdata`をローカルコンピュータのデータディレクトリのフルパスに置き換えてください

3. Dockerイメージのダウンロードが始まり、完了するとbashプロンプトが表示されます。
4. `wp2txt`コマンドはDockerコンテナ内のどこでも使用可能です。入力ダンプファイルと出力テキストファイルの場所として`/data`ディレクトリを使用してください。

**重要:**

- 最高のパフォーマンスを得るために、Docker Desktopのリソース設定（コア数、メモリ量など）を調整してください。
- Dockerコンテナ内で`wp2txt`コマンドを実行する際は、`docker run`コマンドで指定したマウント済みローカルディレクトリ内のどこかに出力ディレクトリを設定してください。

### MacOSとLinuxでのWP2TXT

WP2TXTは`bz2`ファイルを解凍するために、以下のコマンドのいずれかがシステムにインストールされている必要があります：

- `lbzip2`（推奨）
- `pbzip2`
- `bzip2`

ほとんどの場合、`bzip2`コマンドはシステムにプリインストールされています。ただし、`lbzip2`は複数のCPUコアを使用でき、`bzip2`より高速なため、追加でインストールすることをお勧めします。WP2TXTは上記の順序でシステムで利用可能な解凍コマンドを検索します。

Homebrewがインストールされたmacosを使用している場合、以下のコマンドで`lbzip2`をインストールできます：

    $ brew install lbzip2

### WindowsでのWP2TXT

[Bzip2 for Windows](http://gnuwin32.sourceforge.net/packages/bzip2.htm)をインストールし、WP2TXTがbunzip2.exeコマンドを使用できるようにパスを設定してください。または、独自の方法でWikipediaダンプファイルを解凍し、結果のXMLファイルをWP2TXTで処理することもできます。

## インストール

### WP2TXTコマンド

    $ gem install wp2txt

## Wikipediaダンプファイル

### オプション1: 自動ダウンロード（推奨）

WP2TXTはWikipediaダンプを自動的にダウンロードできます。言語コードを指定するだけです：

    $ wp2txt --lang=ja -o ./text

ダンプは`~/.wp2txt/cache/`にダウンロードされ、将来の使用のためにキャッシュされます。キャッシュの確認やクリアが可能です：

    $ wp2txt --cache-status           # キャッシュ状態を表示
    $ wp2txt --cache-clear            # 全キャッシュをクリア
    $ wp2txt --cache-clear --lang=ja  # 日本語のみクリア

キャッシュが設定された有効期限（デフォルト: 30日）より古い場合、wp2txtは警告を表示しますが、キャッシュされたデータの使用は許可されます。`--update-cache`を使用して強制的に新規ダウンロードできます：

    $ wp2txt --lang=ja --from-category="日本の都市" --update-cache -o ./cities

### オプション2: 手動ダウンロード

以下のようなURLから目的の言語の最新Wikipediaダンプファイルをダウンロードします：

    https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles.xml.bz2

ここで`enwiki`は英語Wikipediaを指します。例えば日本語Wikipediaのダンプファイルを取得するには、これを`jawiki`に変更します。その際、上記URLには`enwiki`が2箇所あることに注意してください。

または、[こちら](http://dumps.wikimedia.org/backup-index.html)から特定の日付に作成されたWikipediaダンプファイルを選択することもできます。以下の形式で命名されたファイルをダウンロードしてください：

    xxwiki-yyyymmdd-pages-articles.xml.bz2

ここで`xx`は`en`（英語）や`ja`（日本語）などの言語コード、`yyyymmdd`は作成日（例：`20220801`）です。

## 基本的な使い方

### 自動ダウンロードと処理（推奨）

    $ wp2txt --lang=ja -o ./text

これは日本語Wikipediaダンプを自動的にダウンロードし、プレーンテキストを抽出します。

### タイトルで特定記事を抽出

    $ wp2txt --lang=ja --articles="認知言語学,生成文法" -o ./articles

これは指定された記事のみを抽出します。インデックスファイルと必要なデータストリームのみがダウンロードされるため、フルダンプの処理よりはるかに高速です。

### カテゴリから記事を抽出

    $ wp2txt --lang=ja --from-category="日本の都市" -o ./cities

これは指定されたWikipediaカテゴリに属する全記事を抽出します。`--depth`でサブカテゴリを含めることができます：

    $ wp2txt --lang=ja --from-category="日本の都市" --depth=2 -o ./cities

ダウンロードせずにカテゴリをプレビュー（記事数を表示）：

    $ wp2txt --lang=ja --from-category="日本の都市" --dry-run

自動化用に確認プロンプトをスキップ：

    $ wp2txt --lang=ja --from-category="日本の都市" --yes -o ./cities

### ローカルダンプファイルからプレーンテキストを抽出

    $ wp2txt -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./text

これは圧縮されたダンプファイルを直接ストリーミングし、中間ファイルを作成せずにプレーンテキストを抽出します。

### カテゴリ情報のみを抽出

    $ wp2txt -g -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./category

### 冒頭段落（サマリー）を抽出

    $ wp2txt -s -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./summary

### JSON/JSONLとして出力

    $ wp2txt --format json -i ./enwiki-20220801-pages-articles.xml.bz2 -o ./json

## 出力サンプル

タイトル、カテゴリ情報、段落を含む出力

    $ wp2txt -i ./input -o /output

- [英語Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en.txt)
- [日本語Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja.txt)

タイトルとカテゴリのみを含む出力

    $ wp2txt -g -i ./input -o /output

- [英語Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en_category.txt)
- [日本語Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja_category.txt)

タイトル、カテゴリ、サマリーを含む出力

    $ wp2txt -s -i ./input -o /output

- [英語Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_en_summary.txt)
- [日本語Wikipedia](https://raw.githubusercontent.com/yohasebe/wp2txt/master/data/output_samples/testdata_ja_summary.txt)

### JSON/JSONL出力 (v2.0+)

JSONL形式（1行に1つのJSONオブジェクト）での出力：

    $ wp2txt --format json -i ./input -o /output

各行には以下が含まれます：

```json
{"title": "記事タイトル", "categories": ["カテゴリ1", "カテゴリ2"], "text": "...", "redirect": null}
```

リダイレクト記事の場合：

```json
{"title": "NYC", "categories": [], "text": "", "redirect": "New York City"}
```

### コンテンツタイプマーカー (v2.0+)

デフォルトでは、特殊コンテンツはコンテンツタイプを示すマーカープレースホルダーに置き換えられます：

**インラインマーカー**（文中に出現）：

| マーカー | コンテンツタイプ | MediaWiki例 |
|----------|------------------|-------------|
| `[MATH]` | 数式 | `<math>E=mc^2</math>` |
| `[CODE]` | インラインコード | `<code>variable</code>` |
| `[CHEM]` | 化学式 | `<chem>H2O</chem>` |
| `[IPA]` | IPA発音記号 | `{{IPA|...}}` |

**ブロックマーカー**（独立したコンテンツ）：

| マーカー | コンテンツタイプ | MediaWiki例 |
|----------|------------------|-------------|
| `[CODEBLOCK]` | ソースコードブロック | `<syntaxhighlight>`, `<source>`, `<pre>` |
| `[TABLE]` | Wikiテーブル | `{| ... |}` |
| `[SCORE]` | 楽譜 | `<score>...</score>` |
| `[TIMELINE]` | タイムライングラフィック | `<timeline>...</timeline>` |
| `[GRAPH]` | グラフ/チャート | `<graph>...</graph>` |
| `[INFOBOX]` | 情報ボックス | `{{Infobox ...}}` |
| `[NAVBOX]` | ナビゲーションボックス | `{{Navbox ...}}` |
| `[GALLERY]` | 画像ギャラリー | `<gallery>...</gallery>` |
| `[SIDEBAR]` | サイドバーテンプレート | `{{Sidebar ...}}` |
| `[MAPFRAME]` | インタラクティブ地図 | `<mapframe>...</mapframe>` |
| `[IMAGEMAP]` | クリッカブル画像マップ | `<imagemap>...</imagemap>` |
| `[REFERENCES]` | 参考文献リスト | `{{reflist}}`, `{{refbegin}}...{{refend}}` |

`--markers`でマーカーを設定：

    $ wp2txt --lang=en --markers=all -o ./text        # 全マーカー（デフォルト）
    $ wp2txt --lang=en --markers=math,code -o ./text  # MATHとCODEマーカーのみ

**注意**: `--markers=none`オプションは非推奨です。特殊コンテンツの完全な削除は、周囲のテキストを意味不明にする可能性があります（例：「アインシュタインが発見した。」ではなく「アインシュタインが[MATH]を発見した。」）。

### 引用抽出 (v2.0+)

デフォルトでは、`{{cite book}}`のような引用テンプレートは削除されます。代わりにフォーマットされた引用を抽出するには`--extract-citations`を使用：

    $ wp2txt --lang=en --extract-citations -o ./text

Ruby APIを使用する場合、`extract_citations`オプションでも有効にできます：

```ruby
require 'wp2txt'
include Wp2txt

# デフォルト: 引用は削除される
text = "{{cite book |last=Smith |title=The Book |year=2020}}"
format_wiki(text)
# => ""

# extract_citations: true の場合
format_wiki(text, extract_citations: true)
# => "Smith. \"The Book\". 2020."

# refbegin/refendブロックでも動作
bibliography = "{{refbegin}}\n* {{cite book |last=Author |title=Book |year=2021}}\n{{refend}}"
format_wiki(bibliography, extract_citations: true)
# => "* Author. \"Book\". 2021."
```

サポートされる引用テンプレート：
- `{{cite book}}`, `{{cite web}}`, `{{cite news}}`, `{{cite journal}}`
- `{{cite magazine}}`, `{{cite conference}}`, `{{Citation}}`

## コマンドラインオプション

コマンドラインオプションは以下の通りです：

    Usage: wp2txt [options]

    入力ソース (--input または --lang のいずれかが必須):
      -i, --input=<s>                  圧縮ファイル(bz2)またはXMLファイルへのパス
      -L, --lang=<s>                   自動ダウンロード用Wikipedia言語コード（例: ja, en, de）
      -A, --articles=<s>               抽出する特定の記事タイトル（カンマ区切り、--lang必須）
      -G, --from-category=<s>          Wikipediaカテゴリから記事を抽出（--lang必須）
      -D, --depth=<i>                  --from-categoryのサブカテゴリ再帰深度（デフォルト: 0）
      -y, --yes                        カテゴリ抽出の確認プロンプトをスキップ
      --dry-run                        ダウンロードせずにカテゴリ抽出をプレビュー

    出力オプション:
      -o, --output-dir=<s>             出力ディレクトリへのパス（デフォルト: カレントディレクトリ）
      -j, --format=<s>                 出力形式: text または json (JSONL)（デフォルト: text）

    キャッシュ管理:
      --cache-dir=<s>                  ダウンロードダンプのキャッシュディレクトリ（デフォルト: ~/.wp2txt/cache）
      --cache-status                   キャッシュ状態を表示して終了
      --cache-clear                    キャッシュをクリアして終了（--langで特定言語を指定）
      -U, --update-cache               キャッシュダンプファイルを強制更新（古さを無視）

    設定:
      --config-init                    デフォルト設定ファイルを作成（~/.wp2txt/config.yml）
      --config-path=<s>                設定ファイルへのパス

    処理オプション:
      -a, --category, --no-category    記事のカテゴリ情報を表示（デフォルト: true）
      -g, --category-only              記事タイトルとカテゴリのみを抽出
      -s, --summary-only               記事タイトル、カテゴリ、最初の見出し前のサマリーテキストのみを抽出
      -f, --file-size=<i>              各出力ファイルの概算サイズ（MB）（0で単一ファイル）（デフォルト: 10）
      -n, --num-procs                  同時実行プロセス数（最大8）（デフォルト: 利用可能CPUコア数-2）
      -t, --title, --no-title          出力にページタイトルを保持（デフォルト: true）
      -d, --heading, --no-heading      出力にセクションタイトルを保持（デフォルト: true）
      -l, --list                       未処理のリスト項目を出力に保持
      -r, --ref                        参照表記を[ref]...[/ref]形式で保持
      -e, --redirect                   リダイレクト先を表示
      -m, --marker, --no-marker        リスト項目や定義などのプレフィックス記号を表示（デフォルト: true）
      -k, --markers=<s>                コンテンツタイプマーカー: math,code,chem,table,score,timeline,graph,ipa または 'all'（デフォルト: all）
      -C, --extract-citations          引用を削除せずにフォーマットして抽出
      -b, --bz2-gem                    システムコマンドの代わりにRubyのbzip2-ruby gemを使用
      -v, --version                    バージョンを表示して終了
      -h, --help                       このメッセージを表示

## 設定ファイル

wp2txtは永続的な設定のためにYAML設定ファイルをサポートしています。デフォルト設定を作成：

    $ wp2txt --config-init

これにより`~/.wp2txt/config.yml`が作成されます：

```yaml
cache:
  # ダンプファイルが古いと見なされるまでの日数（1-365）
  dump_expiry_days: 30
  # カテゴリキャッシュの有効期限（1-90）
  category_expiry_days: 7
  # キャッシュディレクトリ
  directory: ~/.wp2txt/cache

defaults:
  # デフォルト出力形式: text または json
  format: text
  # デフォルトサブカテゴリ再帰深度（0-10）
  depth: 0
```

コマンドラインオプションは設定ファイルの設定を上書きします。

## 注意事項

* 数式、コードブロック、化学式などの特殊コンテンツは、デフォルトでプレースホルダー（例：`[MATH]`、`[CODE]`、`[CHEM]`）でマークされます。特定のマーカーのみを表示するには`--markers=math,code`を使用してください。
* さまざまな理由（開始/終了タグの不正なマッチング、言語固有のフォーマットルールなど）により、一部のテキストデータが正しく抽出されない場合があります。
* 変換プロセスには予想以上の時間がかかる場合があります。低スペック環境で英語Wikipediaのような巨大なデータセットを扱う場合、数時間以上かかることがあります。

## 便利なリンク

* [Wikipedia Database backup dumps](http://dumps.wikimedia.org/backup-index.html)

## 著者

* 長谷部陽一郎 (<yohasebe@gmail.com>)

## 参考文献

研究で以下のいずれかを言及していただけると幸いです。

* Yoichiro HASEBE. 2006. [Method for using Wikipedia as Japanese corpus.](http://ci.nii.ac.jp/naid/110006226727) _Doshisha Studies in Language and Culture_ 9(2), 373-403.
* 長谷部陽一郎. 2006. [Wikipedia日本語版をコーパスとして用いた言語研究の手法](http://ci.nii.ac.jp/naid/110006226727). 『言語文化』9(2), 373-403.

または以下のBibTeXエントリを使用：

```
@misc{wp2txt_2026,
  author = {Yoichiro Hasebe},
  title = {WP2TXT: A command-line toolkit to extract text content and category data from Wikipedia dump files},
  url = {https://github.com/yohasebe/wp2txt},
  year = {2026}
}
```

## ライセンス

このソフトウェアはMITライセンスの下で配布されています。LICENSEファイルを参照してください。
