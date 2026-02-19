<img src='https://raw.githubusercontent.com/yohasebe/wp2txt/master/image/wp2txt-logo.svg' width="400" />

Wikipediaダンプファイルからテキストコンテンツとカテゴリデータを抽出するコマンドラインツールキット

[English](README.md) | 日本語

## クイックスタート

```bash
# インストール
gem install wp2txt

# 日本語Wikipediaからテキストを抽出（自動ダウンロード）
wp2txt --lang=ja -o ./output

# 特定の記事を抽出
wp2txt --lang=ja --articles="東京,京都" -o ./articles

# カテゴリから記事を抽出
wp2txt --lang=ja --from-category="日本の都市" -o ./cities
```

## 概要

WP2TXTはWikipediaダンプファイルからプレーンテキストとカテゴリ情報を抽出します。XMLダンプ（bzip2圧縮）を処理し、MediaWikiマークアップを除去して、コーパス言語学やテキストマイニングなどの研究に適したクリーンなテキストを出力します。

## 主な機能

- **自動ダウンロード** - 言語コード指定でダンプを自動ダウンロード
- **タイトル指定抽出** - フルダンプをダウンロードせずに特定記事を抽出
- **カテゴリベース抽出** - 特定のWikipediaカテゴリから全記事を抽出
- **カテゴリメタデータ抽出** - 記事のカテゴリ情報を出力に保持
- **テンプレート展開** - 日付・単位・座標などの一般的なテンプレートを可読テキストに変換
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

## インストール

### wp2txtのインストール

    $ gem install wp2txt

### システム要件

WP2TXTは`bz2`ファイルを解凍するために、以下のコマンドのいずれかが必要です：

- `lbzip2`（推奨 - 複数CPUコアを使用）
- `pbzip2`
- `bzip2`（ほとんどのシステムにプリインストール済み）

macOS（Homebrew）：

    $ brew install lbzip2

Windows：[Bzip2 for Windows](http://gnuwin32.sourceforge.net/packages/bzip2.htm)をインストールしてPATHに追加。

### Docker（代替方法）

```shell
docker run -it -v /path/to/localdata:/data yohasebe/wp2txt
```

`wp2txt`コマンドはコンテナ内で使用可能です。入出力には`/data`ディレクトリを使用してください。

## 基本的な使い方

### 自動ダウンロードと処理（推奨）

    $ wp2txt --lang=ja -o ./text

日本語Wikipediaダンプを自動的にダウンロードし、プレーンテキストを抽出します。ダウンロードは`~/.wp2txt/cache/`にキャッシュされます。

### タイトルで特定記事を抽出

    $ wp2txt --lang=ja --articles="認知言語学,生成文法" -o ./articles

インデックスファイルと必要なデータストリームのみがダウンロードされるため、フルダンプの処理よりはるかに高速です。

### カテゴリから記事を抽出

    $ wp2txt --lang=ja --from-category="日本の都市" -o ./cities

`--depth`でサブカテゴリを含める：

    $ wp2txt --lang=ja --from-category="日本の都市" --depth=2 -o ./cities

ダウンロードせずにプレビュー（記事数を表示）：

    $ wp2txt --lang=ja --from-category="日本の都市" --dry-run

### ローカルダンプファイルを処理

    $ wp2txt -i ./jawiki-20220801-pages-articles.xml.bz2 -o ./text

### その他の抽出モード

    # カテゴリ情報のみ（タイトル + カテゴリ）
    $ wp2txt -g --lang=ja -o ./category

    # サマリーのみ（タイトル + カテゴリ + 冒頭段落）
    $ wp2txt -s --lang=ja -o ./summary

    # JSON/JSONL出力
    $ wp2txt --format json --lang=ja -o ./json

## 出力サンプル

### テキスト出力

```
[[記事タイトル]]

記事の内容がセクションと段落で表示されます...

CATEGORIES: カテゴリ1, カテゴリ2, カテゴリ3
```

### JSON/JSONL出力

各行に1つのJSONオブジェクト：

```json
{"title": "記事タイトル", "categories": ["カテゴリ1", "カテゴリ2"], "text": "...", "redirect": null}
```

リダイレクト記事の場合：

```json
{"title": "NYC", "categories": [], "text": "", "redirect": "New York City"}
```

## キャッシュ管理

    $ wp2txt --cache-status           # キャッシュ状態を表示
    $ wp2txt --cache-clear            # 全キャッシュをクリア
    $ wp2txt --cache-clear --lang=ja  # 日本語のみクリア
    $ wp2txt --update-cache           # 強制的に新規ダウンロード

キャッシュが有効期限（デフォルト: 30日）を超えると、wp2txtは警告を表示しますが、キャッシュされたデータの使用は許可されます。

## Wikipediaダンプファイル（手動ダウンロード）

手動でダウンロードする場合：

    https://dumps.wikimedia.org/jawiki/latest/jawiki-latest-pages-articles.xml.bz2

`jawiki`を対象言語に置き換えてください（例：英語は`enwiki`）。ファイル名の形式：

    xxwiki-yyyymmdd-pages-articles.xml.bz2

`xx`は言語コード、`yyyymmdd`は作成日です。

## 詳細オプション

### コンテンツタイプマーカー

特殊コンテンツはデフォルトでマーカープレースホルダーに置き換えられます：

**インラインマーカー**（文中に出現）：

| マーカー | コンテンツタイプ |
|----------|------------------|
| `[MATH]` | 数式 |
| `[CODE]` | インラインコード |
| `[CHEM]` | 化学式 |
| `[IPA]` | IPA発音記号 |

**ブロックマーカー**（独立したコンテンツ）：

| マーカー | コンテンツタイプ |
|----------|------------------|
| `[CODEBLOCK]` | ソースコードブロック |
| `[TABLE]` | Wikiテーブル |
| `[INFOBOX]` | 情報ボックス |
| `[NAVBOX]` | ナビゲーションボックス |
| `[GALLERY]` | 画像ギャラリー |
| `[REFERENCES]` | 参考文献リスト |
| `[SCORE]` | 楽譜 |
| `[TIMELINE]` | タイムライングラフィック |
| `[GRAPH]` | グラフ/チャート |
| `[SIDEBAR]` | サイドバーテンプレート |
| `[MAPFRAME]` | インタラクティブ地図 |
| `[IMAGEMAP]` | クリッカブル画像マップ |

`--markers`で設定：

    $ wp2txt --lang=ja --markers=all -o ./text        # 全マーカー（デフォルト）
    $ wp2txt --lang=ja --markers=math,code -o ./text  # MATHとCODEのみ

**注意**: `--markers=none`は非推奨です。特殊コンテンツの完全な削除は周囲のテキストを意味不明にする可能性があります。

### テンプレート展開

一般的なMediaWikiテンプレートは自動的に展開されます（デフォルトで有効）：

| テンプレート | 出力 |
|--------------|------|
| `{{birth date\|1990\|5\|15}}` | May 15, 1990 |
| `{{convert\|100\|km\|mi}}` | 100 km (62 mi) |
| `{{coord\|35\|41\|N\|139\|41\|E}}` | 35°41′N 139°41′E |
| `{{lang\|ja\|日本語}}` | 日本語 |
| `{{nihongo\|Tokyo\|東京\|Tōkyō}}` | Tokyo (東京, Tōkyō) |
| `{{frac\|1\|2}}` | 1/2 |
| `{{circa\|1900}}` | c. 1900 |

サポート対象：日付/年齢テンプレート、単位変換、座標、言語タグ、引用、分数など。パーサー関数（`{{#if:}}`、`{{#switch:}}`）とマジックワード（`{{PAGENAME}}`、`{{CURRENTYEAR}}`）もサポート。

`--no-expand-templates`で無効化。

### 引用抽出

デフォルトでは引用テンプレートは削除されます。`--extract-citations`でフォーマットされた引用を抽出：

    $ wp2txt --lang=ja --extract-citations -o ./text

サポート対象：`{{cite book}}`、`{{cite web}}`、`{{cite news}}`、`{{cite journal}}`、`{{Citation}}`など。

## コマンドラインオプション

    Usage: wp2txt [options]

    入力ソース（--input または --lang のいずれかが必須）:
      -i, --input=<s>                  圧縮ファイル(bz2)またはXMLファイルへのパス
      -L, --lang=<s>                   Wikipedia言語コード（例: ja, en, de）
      -A, --articles=<s>               特定の記事タイトル（カンマ区切り）
      -G, --from-category=<s>          Wikipediaカテゴリから記事を抽出
      -D, --depth=<i>                  サブカテゴリ再帰深度（デフォルト: 0）
      -y, --yes                        確認プロンプトをスキップ
      --dry-run                        カテゴリ抽出をプレビュー

    出力オプション:
      -o, --output-dir=<s>             出力ディレクトリ（デフォルト: カレント）
      -j, --format=<s>                 出力形式: text または json（デフォルト: text）

    キャッシュ管理:
      --cache-dir=<s>                  キャッシュディレクトリ（デフォルト: ~/.wp2txt/cache）
      --cache-status                   キャッシュ状態を表示して終了
      --cache-clear                    キャッシュをクリアして終了
      -U, --update-cache               キャッシュファイルを強制更新

    設定:
      --config-init                    デフォルト設定を作成（~/.wp2txt/config.yml）
      --config-path=<s>                設定ファイルへのパス

    処理オプション:
      -a, --category, --no-category    カテゴリ情報を表示（デフォルト: true）
      -g, --category-only              タイトルとカテゴリのみ抽出
      -s, --summary-only               タイトル、カテゴリ、サマリーを抽出
      -f, --file-size=<i>              出力ファイルサイズ（MB）（デフォルト: 10, 0=単一）
      -n, --num-procs                  並列プロセス数（最大8, デフォルト: 自動）
      -t, --title, --no-title          ページタイトルを保持（デフォルト: true）
      -d, --heading, --no-heading      セクションタイトルを保持（デフォルト: true）
      -l, --list                       リスト項目を保持
      -r, --ref                        参照を[ref]...[/ref]形式で保持
      -e, --redirect                   リダイレクト先を表示
      -m, --marker, --no-marker        リストマーカーを表示（デフォルト: true）
      -k, --markers=<s>                コンテンツマーカー（デフォルト: all）
      -C, --extract-citations          フォーマットされた引用を抽出
      -E, --expand-templates           テンプレートを展開（デフォルト: true）
          --no-expand-templates        テンプレート展開を無効化
      -b, --bz2-gem                    bzip2-ruby gemを使用
      -v, --version                    バージョンを表示
      -h, --help                       ヘルプを表示

## 設定ファイル

永続的な設定を作成：

    $ wp2txt --config-init

`~/.wp2txt/config.yml`が作成されます：

```yaml
cache:
  dump_expiry_days: 30      # ダンプが古いと見なされるまでの日数（1-365）
  category_expiry_days: 7   # カテゴリキャッシュの有効期限（1-90）
  directory: ~/.wp2txt/cache

defaults:
  format: text              # デフォルト出力形式
  depth: 0                  # デフォルトサブカテゴリ深度
```

コマンドラインオプションは設定ファイルの設定を上書きします。

## 注意事項

* 特殊コンテンツ（数式、コードなど）はデフォルトでプレースホルダーでマークされます。
* マークアップのバリエーションや言語固有のフォーマットにより、一部のテキストが正しく抽出されない場合があります。
* 大規模ダンプ（例：英語Wikipedia）の処理は、低スペック環境では数時間かかることがあります。

## 変更履歴

詳細なリリースノートは[CHANGELOG.md](CHANGELOG.md)を参照してください。

**v2.0.0（2026年1月）**: 自動ダウンロードモード、カテゴリベース抽出、タイトル指定抽出、JSON出力、コンテンツマーカー、テンプレート展開、ストリーミング処理、Ruby 4.0サポート。

## 便利なリンク

* [Wikipedia Database backup dumps](http://dumps.wikimedia.org/backup-index.html)

## 著者

* 長谷部陽一郎 (<yohasebe@gmail.com>)

## 参考文献

研究で以下のいずれかを言及していただけると幸いです。

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

## ライセンス

このソフトウェアはMITライセンスの下で配布されています。LICENSEファイルを参照してください。
