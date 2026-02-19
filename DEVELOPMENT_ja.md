# WP2TXT 開発ガイド

このドキュメントはWP2TXTの開発者向けガイダンスを提供します。ユーザードキュメントは[README_ja.md](README_ja.md)を参照してください。

[English](DEVELOPMENT.md) | 日本語

## クイックスタート

```bash
# 依存関係をインストール
bundle install

# テストを実行
bundle exec rspec

# カバレッジ付きでテストを実行
bundle exec rspec  # カバレッジレポートは coverage/index.html
```

## アーキテクチャ概要

### 処理パイプライン

WP2TXTはWikipediaダンプを処理するためにストリーミングアーキテクチャを使用します：

```
入力 (bz2/xml) → StreamProcessor → Article Parser → OutputWriter → 出力ファイル
```

1. **StreamProcessor** (`lib/wp2txt.rb`): bz2を解凍しXMLページをストリーミング
2. **Article** (`lib/wp2txt/article.rb`): MediaWikiテキストを型付き要素にパース
3. **Utils** (`lib/wp2txt/utils.rb`): テキストフォーマットとクリーンアップ関数を提供
4. **OutputWriter** (`lib/wp2txt.rb`): テキストまたはJSON形式で出力を書き込み

### コアクラス

| クラス | ファイル | 目的 |
|--------|----------|------|
| `StreamProcessor` | `lib/wp2txt/stream_processor.rb` | 適応的バッファリングで圧縮ダンプからページをストリーミング |
| `Article` | `lib/wp2txt/article.rb` | MediaWikiマークアップをパース |
| `OutputWriter` | `lib/wp2txt.rb` | 出力ファイルローテーションを管理 |
| `DumpManager` | `lib/wp2txt/multistream.rb` | ダンプをダウンロード・キャッシュ |
| `MultistreamIndex` | `lib/wp2txt/multistream.rb` | ランダムアクセス用に記事をインデックス化 |
| `MultistreamReader` | `lib/wp2txt/multistream.rb` | 記事を抽出（並列抽出対応） |
| `CategoryFetcher` | `lib/wp2txt/multistream.rb` | Wikipedia APIからカテゴリメンバーを取得 |
| `MemoryMonitor` | `lib/wp2txt/memory_monitor.rb` | クロスプラットフォームメモリ監視 |
| `Bz2Validator` | `lib/wp2txt/bz2_validator.rb` | bz2ファイルの整合性を検証 |
| `CLI` | `lib/wp2txt/cli.rb` | コマンドラインオプションのパース |

### キャッシュクラス

| クラス | ファイル | 目的 |
|--------|----------|------|
| `GlobalDataCache` | `lib/wp2txt/global_data_cache.rb` | パース済みJSONデータファイルのSQLiteキャッシュ |
| `CategoryCache` | `lib/wp2txt/category_cache.rb` | Wikipediaカテゴリ階層のSQLiteキャッシュ |
| `IndexCache` | `lib/wp2txt/index_cache.rb` | マルチストリームインデックスエントリのSQLiteキャッシュ |

### 要素タイプ

`Article`クラスはMediaWikiテキストを型付き要素にパースします：

| タイプ | 説明 |
|--------|------|
| `:mw_heading` | セクション見出し (`== タイトル ==`) |
| `:mw_paragraph` | 通常のテキスト段落 |
| `:mw_table` | Wikiテーブル (`{| ... |}`) |
| `:mw_quote` | ブロッククォート |
| `:mw_pre` | 整形済みテキスト |
| `:mw_unordered` | 順序なしリスト項目 |
| `:mw_ordered` | 順序付きリスト項目 |
| `:mw_definition` | 定義リスト項目 |
| `:mw_link` | 単一行リンク |
| `:mw_ml_link` | 複数行リンク |
| `:mw_redirect` | リダイレクトページ |
| `:mw_template` | テンプレート |
| `:mw_isolated_tag` | HTMLタグ |

### マーカーシステム

コンテンツタイプマーカーは特殊コンテンツ（math、codeなど）をプレースホルダーに置き換えます：

```ruby
# utils.rb内
MARKER_TYPES = %i[math code chem table score timeline graph ipa].freeze

# 処理フロー:
# 1. コンテンツ検出 → プレースホルダーに置換 («« MATH »»)
# 2. テキスト処理続行（プレースホルダーはクリーンアップから保護）
# 3. finalize_markers() がプレースホルダーを [MARKER] 形式に変換
```

### テンプレート展開

`TemplateExpander`クラス（`lib/wp2txt/template_expander.rb`）は一般的なWikipediaテンプレートを可読テキストに展開します：

| テンプレートタイプ | 例 | 出力 |
|--------------------|-----|------|
| 生年月日/没年月日 | `{{birth date|1990|5|15}}` | "May 15, 1990" |
| 単位変換 | `{{convert|100|km|mi}}` | "100 km (62 mi)" |
| 座標 | `{{coord|35|41|N|139|41|E}}` | "35°41′N 139°41′E" |
| 言語タグ | `{{lang|ja|日本語}}` | "日本語" |
| 仮名 | `{{nihongo|Tokyo|東京|Tōkyō}}` | "Tokyo (東京, Tōkyō)" |

テンプレート展開はデフォルトで有効です。`--no-expand-templates`または`expand_templates: false`で無効化できます。

### マジックワード展開

`MagicWordExpander`クラス（`lib/wp2txt/magic_words.rb`）はMediaWikiマジックワードを実際の値に展開します：

| カテゴリ | マジックワード | 例 |
|----------|----------------|-----|
| ページ文脈 | `PAGENAME`, `FULLPAGENAME`, `BASEPAGENAME`, `ROOTPAGENAME`, `SUBPAGENAME`, `NAMESPACE`, `TALKPAGENAME` | `{{PAGENAME}}` → "記事タイトル" |
| 日時 | `CURRENTYEAR`, `CURRENTMONTH`, `CURRENTDAY`, `CURRENTDAYNAME`, `CURRENTTIME`, `CURRENTTIMESTAMP` | `{{CURRENTYEAR}}` → "2024" |
| 文字列関数 | `lc`, `uc`, `lcfirst`, `ucfirst`, `urlencode`, `anchorencode`, `padleft`, `padright` | `{{uc:hello}}` → "HELLO" |
| パーサー関数 | `#titleparts` | `{{#titleparts:A/B/C\|2}}` → "A/B" |

マジックワードは`format_wiki()`パイプラインの早い段階で、configにtitleが指定されている場合に展開されます：

```ruby
result = format_wiki(text, title: "記事名", dump_date: Time.now)
```

## キャッシングインフラストラクチャ

WP2TXTはSQLiteベースのキャッシュを使用して、繰り返し実行時のパフォーマンスを向上させています。すべてのキャッシュは `~/.wp2txt/cache/` に保存されます。

### GlobalDataCache

パース済みJSONデータファイル（テンプレート、MediaWikiエイリアス、HTMLエンティティ）をキャッシュし、パースのオーバーヘッドを削減：

```ruby
# 自動 - データ読み込みメソッドは透過的にキャッシュを使用
data = Wp2txt.load_mediawiki_data  # 有効であればキャッシュを使用

# 手動キャッシュ操作
Wp2txt::GlobalDataCache.clear!     # キャッシュをすべてクリア
Wp2txt::GlobalDataCache.stats      # キャッシュ統計を取得
```

キャッシュ検証：ソースファイルの変更時刻とサイズをチェックします。ソースファイルが変更されると自動的にキャッシュは無効化されます。

### CategoryCache

Wikipedia APIからのカテゴリ階層をキャッシュし、カテゴリベースの記事抽出を高速化：

```ruby
cache = Wp2txt::CategoryCache.new("en", cache_dir: "/path/to/cache")

# カテゴリデータを保存
cache.save("カテゴリ名", ["記事1", "記事2"], ["サブカテゴリ1"])

# カテゴリデータを取得
data = cache.get("カテゴリ名")  # { pages: [...], subcats: [...] }

# カテゴリツリー内のすべてのページを取得
pages = cache.get_all_pages("ルートカテゴリ", max_depth: 2)

# 統計とメンテナンス
cache.stats              # キャッシュ統計
cache.cleanup_expired!   # 古いエントリを削除
cache.clear!             # すべてクリア
```

### IndexCache

パース済みマルチストリームインデックスエントリをキャッシュし、記事の高速検索を実現：

```ruby
cache = Wp2txt::IndexCache.new("/path/to/index.txt", cache_dir: "/path/to/cache")

# キャッシュの有効性を確認
cache.valid?  # キャッシュが存在しソースファイルと一致する場合 true

# 保存/読み込み操作（MultistreamIndexで内部的に使用）
cache.save(entries_by_title, stream_offsets)
data = cache.load  # { entries_by_title: {}, entries_by_id: {}, stream_offsets: [] }

# バッチ検索
results = cache.find_by_titles(["記事1", "記事2"])
```

### キャッシュの場所

すべてのキャッシュは `~/.wp2txt/cache/` に保存されます：

```
~/.wp2txt/cache/
├── global_data.sqlite3           # GlobalDataCache
├── categories_en.sqlite3         # CategoryCache（英語）
├── categories_ja.sqlite3         # CategoryCache（日本語）
└── enwiki_*_index.sqlite3        # IndexCache（ダンプファイルごと）
```

## テストシステム

### テスト構造

```
spec/
├── spec_helper.rb          # RSpec設定
├── article_spec.rb         # 記事パーステスト
├── utils_spec.rb           # テキスト処理テスト
├── markers_spec.rb         # マーカー機能テスト
├── auto_download_spec.rb   # CLIとダウンロードテスト
├── multilingual_spec.rb    # 言語固有テスト
├── streaming_spec.rb       # ストリーミングアーキテクチャテスト
└── testdata/               # 静的テストデータ
```

### テストの実行

```bash
# 全テストを実行
bundle exec rspec

# 特定のテストファイルを実行
bundle exec rspec spec/utils_spec.rb

# ドキュメント形式で実行
bundle exec rspec --format documentation

# 行番号で特定のテストを実行
bundle exec rspec spec/utils_spec.rb:42
```

## マルチストリームサポート

WP2TXTは効率的な記事抽出のためにWikipediaのマルチストリーム形式をサポートしています。

### マルチストリームの仕組み

1. **インデックスファイル** (`-multistream-index.txt.bz2`): 記事タイトルをバイトオフセットにマッピング
2. **マルチストリームファイル** (`-multistream.xml.bz2`): 連結されたbz2ストリーム

### 並列抽出

`MultistreamReader`はパフォーマンス向上のための並列記事抽出をサポートしています：

```ruby
reader = MultistreamReader.new(multistream_path, index_path)

# 複数の記事を並列で抽出（デフォルト4プロセス）
results = reader.extract_articles_parallel(["東京", "京都", "大阪"], num_processes: 4)

# 並列処理でイテレート
reader.each_article_parallel(entries, num_processes: 4) do |page|
  process(page)
end
```

記事はストリームオフセットでグループ化され、bz2解凍のオーバーヘッドを最小化します。

### 部分ダウンロード

特定の記事抽出では、WP2TXTは必要なデータのみをダウンロードします：

```ruby
# 最初のNストリームのみダウンロード
manager.download_multistream(max_streams: 10)

# 必要なバイト範囲のみダウンロード
download_file_range(url, path, start_byte, end_byte)
```

### 差分ダウンロード

部分ダンプが存在する場合、`download_multistream_full`はダウンロードを再開できます：

```ruby
manager = DumpManager.new("ja")

# 既存の部分ダンプを確認
partial = manager.find_any_partial_cache
# => { path: "...", dump_date: "20260101", stream_count: 100, size: 1000000, mtime: ... }

# 差分ダウンロードが可能か確認
resume_info = manager.can_resume_from_partial?(partial)
# => { possible: true, current_streams: 100, total_streams: 5000, current_size: 1000000 }
# => { possible: false, reason: :date_mismatch, partial_date: "20250101", latest_date: "20260101" }

# 差分ダウンロードサポート付きでフルダンプをダウンロード（対話式プロンプト）
path = manager.download_multistream_full(interactive: true)

# 非対話モード（ユーザープロンプトをスキップ、必要に応じて常に新規ダウンロード）
path = manager.download_multistream_full(interactive: false)
```

差分ダウンロードのユーザープロンプト：

1. **同一日付の部分ダンプが存在:**
   - `[Y]` ダウンロードを再開（残りのデータのみダウンロード）
   - `[n]` 既存の部分ダンプをそのまま使用
   - `[f]` 新規フルダンプをダウンロード

2. **古い部分ダンプが存在:**
   - `[D]` 古い部分を削除して最新をダウンロード（推奨）
   - `[k]` 古い部分を保持、最新を別途ダウンロード
   - `[u]` 古い部分をそのまま使用（内容が古い可能性あり）

### 記事抽出フロー

```
1. インデックスファイルをダウンロード（英語版で約500MB）
2. インデックスをハッシュにロード（O(1)ルックアップ）
3. 記事オフセットを検索
4. ストリームオフセットでグループ化
5. 必要なストリームのみダウンロード
6. 特定の記事を抽出
```

## メモリ管理

WP2TXTには大規模ダンプ処理のための適応型メモリ管理が含まれています：

### MemoryMonitor

`lib/wp2txt/memory_monitor.rb`でのクロスプラットフォームメモリ監視：

```ruby
# 現在のメモリ使用量を確認
stats = Wp2txt::MemoryMonitor.memory_stats
# => { current: 256000000, available: 8000000000, ... }

# 利用可能メモリに基づく最適バッファサイズを取得
buffer_size = Wp2txt::MemoryMonitor.optimal_buffer_size
# => 10485760 (10 MB)

# メモリが少ない場合GCをトリガー
Wp2txt::MemoryMonitor.gc_if_needed
```

### StreamProcessorの適応的バッファリング

`StreamProcessor`はバッファサイズを動的に調整します：

```ruby
processor = Wp2txt::StreamProcessor.new(input_path, adaptive_buffer: true)
processor.each_page { |title, text| ... }

# 処理統計を監視
processor.stats
# => { pages_processed: 1000, bytes_read: 50000000, buffer_size: 10485760, ... }
```

## bz2検証

`Bz2Validator`モジュールは処理前にbz2ファイルを検証します：

```ruby
# 完全検証（ヘッダー + 解凍テスト）
result = Wp2txt::Bz2Validator.validate("/path/to/file.bz2")
result.valid?      # => true/false
result.error_type  # => :invalid_magic, :too_small など
result.message     # => "Invalid bz2 header..."

# クイック検証（ヘッダーのみ）
result = Wp2txt::Bz2Validator.validate_quick("/path/to/file.bz2")

# ファイル情報を取得
info = Wp2txt::Bz2Validator.file_info("/path/to/file.bz2")
# => { path: "...", size: 1000000, valid_header: true, version: "h", block_size: 9, ... }
```

## 新機能の追加

### 新しいマーカータイプの追加

1. `lib/wp2txt/utils.rb`の`MARKER_TYPES`に追加
2. `apply_markers()`に検出パターンを追加
3. `spec/markers_spec.rb`にテストを追加

### 新しいCLIオプションの追加

1. `lib/wp2txt/cli.rb`にオプション定義を追加
2. `validate_options!()`にバリデーションを追加
3. `bin/wp2txt`でオプションを処理
4. `spec/auto_download_spec.rb`にテストを追加
5. README.mdを更新

### 言語サポートの追加

1. カテゴリキーワード: `data/language_categories.json`
2. リダイレクトキーワード: `data/language_redirects.json`
3. スクリプト: `scripts/generate_language_data.rb`

## コードスタイル

- Ruby 2.6+互換性
- フローズンストリングリテラル (`# frozen_string_literal: true`)
- RuboCop設定は`.rubocop.yml`
- 全体でUTF-8エンコーディング

## Docker

Dockerイメージのビルドとプッシュ：

```bash
rake push  # マルチアーキテクチャでビルドしDocker Hubにプッシュ
```

## リリースプロセス

1. `lib/wp2txt/version.rb`のバージョンを更新
2. CHANGELOG.mdを更新
3. フルテストスイートを実行: `bundle exec rspec`
4. gemをビルド: `gem build wp2txt.gemspec`
5. RubyGemsにプッシュ: `gem push wp2txt-*.gem`
6. Dockerイメージをプッシュ: `rake push`
7. GitHubリリースを作成

## 便利なリンク

- [MediaWikiマークアップリファレンス](https://www.mediawiki.org/wiki/Help:Formatting)
- [Wikipediaダンプダウンロード](https://dumps.wikimedia.org/)
- [マルチストリーム形式](https://meta.wikimedia.org/wiki/Data_dumps/FAQ#Why_are_there_multiple_files_for_a_single_dump?)
