# セクション選択的抽出機能 仕様書

**作成日:** 2026-01-10
**作成元:** EngTagger 2.0プロジェクト
**ステータス:** 提案段階
**最終更新:** 2026-01-10

---

## 1. 概要

Wikipedia記事から特定のセクションを選択的に抽出する機能。NLPモデルの学習コーパス構築において、構文的に多様なテキストを効率的に収集することを目的とする。

### 背景

- Wikipediaのサマリー（冒頭部分）は百科事典的な文体に偏る
- 特定のセクション（Plot, Reception等）は異なる構文パターンを持つ
- セクションを選択的に抽出することで、構文的に多様なコーパスを構築できる

### 用語定義

| 用語 | 定義 |
|------|------|
| **サマリー (summary)** | 記事冒頭から最初の見出しまでのテキスト。リード文、導入部とも呼ばれる |
| **セクション (section)** | 見出しで区切られた記事の一部分 |
| **セクションレベル** | 見出しの階層（`==`=Level 2, `===`=Level 3, ...） |

---

## 2. CLI インターフェース

### 新規フラグ

```bash
--sections NAMES         # 抽出するセクション名（カンマ区切り）
--section-output MODE    # 出力モード: structured (デフォルト) / combined
--min-section-length N   # 最小文字数（これより短いセクションは除外）
```

### 使用例

```bash
# サマリー + 特定セクションを抽出（1回のパスで複数セクション）
wp2txt -i enwiki-dump.xml.bz2 -j json --sections "summary,Plot,Reception,Early life"

# セクションのみ（サマリーなし）
wp2txt -i enwiki-dump.xml.bz2 -j json --sections "Plot,Reception"

# サマリーのみ（既存動作と同等）
wp2txt -i enwiki-dump.xml.bz2 -j json --sections "summary"

# 学習データ用（全テキスト連結）
wp2txt -i enwiki-dump.xml.bz2 -j json --sections "summary,Plot" --section-output combined

# 短いセクションを除外
wp2txt -i enwiki-dump.xml.bz2 -j json --sections "summary,Plot" --min-section-length 100

# サマリーのみ（既存動作、後方互換）
wp2txt -i enwiki-dump.xml.bz2 -j json --summary-only
```

### 予約語: `summary`

`--sections` リスト内で `summary` はサマリー（冒頭テキスト）を指す予約語として扱う。

```bash
--sections "summary"              # サマリーのみ
--sections "summary,Plot"         # サマリー + Plot
--sections "Plot,Reception"       # Plot + Reception（サマリーなし）
--sections "summary,Plot,summary" # エラーまたは重複無視
```

### フラグの組み合わせ

| フラグ | 動作 |
|--------|------|
| (なし) | 全テキストを出力（既存動作） |
| `--summary-only` | サマリーのみ（既存動作、後方互換） |
| `--sections "summary"` | サマリーのみ（新方式） |
| `--sections "summary,A,B"` | サマリー + 指定セクション |
| `--sections "A,B"` | 指定セクションのみ（サマリーなし） |

---

## 3. 出力フォーマット

### 3.1 Structured モード（デフォルト: `--section-output structured`）

分析・検証用。セクションごとに分離して出力。

**JSON出力（`--format json`）:**

```json
{
  "title": "The Shawshank Redemption",
  "sections": {
    "summary": "The Shawshank Redemption is a 1994 American prison drama film...",
    "Plot": "In 1947, banker Andy Dufresne is convicted of murdering...",
    "Reception": "The film received critical acclaim. Roger Ebert called it..."
  },
  "categories": ["1994 films", "American drama films", "Prison films"]
}
```

**セクションが存在しない場合:**

```json
{
  "title": "Albert Einstein",
  "sections": {
    "summary": "Albert Einstein was a German-born theoretical physicist...",
    "Early life": "Einstein was born in Ulm, in the Kingdom of Württemberg...",
    "Plot": null,
    "Reception": null
  },
  "categories": ["1879 births", "German physicists"]
}
```

- 指定されたが存在しないセクションは `null` として出力
- これにより、どのセクションが要求されたか追跡可能
- `summary` も他のセクションと同様に `sections` オブジェクト内に格納

**テキスト出力（`--format text`）:**

```
TITLE: The Shawshank Redemption

SECTION [summary]:
The Shawshank Redemption is a 1994 American prison drama film...

SECTION [Plot]:
In 1947, banker Andy Dufresne is convicted of murdering...

SECTION [Reception]:
The film received critical acclaim. Roger Ebert called it...

CATEGORIES: 1994 films, American drama films, Prison films

```

### 3.2 Combined モード（`--section-output combined`）

学習データ用。全セクションを連結して単一テキストとして出力。

**JSON出力:**

```json
{
  "title": "The Shawshank Redemption",
  "text": "The Shawshank Redemption is a 1994 American prison drama film...\n\nIn 1947, banker Andy Dufresne is convicted of murdering...\n\nThe film received critical acclaim. Roger Ebert called it...",
  "sections_included": ["summary", "Plot", "Reception"],
  "categories": ["1994 films", "American drama films", "Prison films"]
}
```

**フィールド仕様:**

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `title` | string | 記事タイトル |
| `text` | string | 連結されたテキスト（セクション間は `\n\n` で区切り） |
| `sections_included` | array | 実際に含まれたセクション名のリスト |
| `categories` | array | カテゴリ名のリスト |

**テキスト出力:**

```
TITLE: The Shawshank Redemption
SECTIONS: summary, Plot, Reception

The Shawshank Redemption is a 1994 American prison drama film...

In 1947, banker Andy Dufresne is convicted of murdering...

The film received critical acclaim. Roger Ebert called it...

CATEGORIES: 1994 films, American drama films, Prison films

```

### 3.3 フィールド仕様（Structured モード）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `title` | string | 記事タイトル |
| `sections` | object | セクション名→テキストのマップ（`summary` を含む） |
| `categories` | array | カテゴリ名のリスト |

---

## 4. セクション名のマッチング

### 4.1 基本マッチングルール

1. **大文字小文字を区別しない** (case-insensitive)
2. **部分一致ではなく完全一致**（デフォルト）
3. **前後の空白は無視**
4. **見出しレベルは問わない**（`== Plot ==` も `=== Plot ===` も対象）

### 例

| 指定 | マッチする見出し | マッチしない見出し |
|------|-----------------|-------------------|
| `Plot` | `== Plot ==`, `=== Plot ===` | `== Plot summary ==` |
| `Early life` | `== Early life ==` | `== Early Life and Education ==` |
| `Reception` | `== Reception ==` | `== Critical reception ==` |

### 4.2 セクションエイリアス（同義語）

同じ意味を持つセクション名をグループ化。いずれかが見つかれば抽出。

**方針: データ駆動アプローチ**

組み込みエイリアスは最小限に留め、実データの分析結果に基づいてユーザーが定義する。

```
1. --metadata-only でセクション名の分布を調査
2. 類似セクション名を特定（Plot/Synopsis等）
3. --alias-file でカスタムエイリアスを指定
```

**最小限の組み込みエイリアス:**

```yaml
# 確実に同義と言えるもののみ
Plot: [Synopsis]
Reception: [Critical reception]
```

**カスタムエイリアスファイル (YAML):**

```yaml
# custom_aliases.yml
Plot:
  - Synopsis
  - Story
  - Storyline
Reception:
  - Critical reception
  - Critical response
Early life:
  - Early years
  - Childhood
```

**CLIでの指定:**

```bash
# 組み込みエイリアスのみ（デフォルト）
wp2txt --sections "Plot,Reception"

# エイリアスを無効化（完全一致のみ）
wp2txt --sections "Plot,Reception" --no-section-aliases

# カスタムエイリアスファイルを指定
wp2txt --sections "Plot,Reception" --alias-file custom_aliases.yml
```

**出力での扱い:**

```json
{
  "title": "Movie Title",
  "sections": {
    "Plot": "...",           // "Synopsis" にマッチしても "Plot" として出力
    "Reception": "..."       // "Critical reception" にマッチしても "Reception" として出力
  },
  "matched_sections": {      // 実際にマッチした見出し名（デバッグ用、オプション）
    "Plot": "Synopsis",
    "Reception": "Critical reception"
  }
}
```

### 4.3 拡張マッチング（将来的なオプション）

```bash
--section-match exact     # 完全一致（デフォルト）
--section-match partial   # 部分一致を許可
--section-match regex     # 正規表現マッチング
```

現時点では完全一致 + エイリアスのみ実装。

---

## 5. 推奨セクション名（英語Wikipedia）

### Tier 1: 高優先度

| セクション名 | 出現頻度 | 構文的特徴 |
|-------------|---------|-----------|
| `Plot` | 映画・本・ゲーム記事 | 物語時制、直接話法 |
| `Synopsis` | 同上（Plotの別名） | 同上 |
| `Reception` | 作品記事 | 引用、評価表現 |
| `Critical reception` | 同上 | 同上 |
| `Early life` | 人物記事 | 過去形、時間表現 |
| `History` | 組織・場所記事 | 過去形、因果関係 |

### Tier 2: 中優先度

| セクション名 | 出現頻度 | 構文的特徴 |
|-------------|---------|-----------|
| `Career` | 人物記事 | 業績の記述 |
| `Biography` | 人物記事 | 過去形 |
| `Description` | 場所・種・物品記事 | 現在形、形容詞 |
| `Gameplay` | ゲーム記事 | 条件文、命令表現 |
| `Legacy` | 人物・作品記事 | 評価表現 |
| `Personal life` | 人物記事 | 過去形、引用 |

---

## 6. サブセクションの扱い

### デフォルト動作

指定されたセクションとその全サブセクションを含む。

```
== Reception ==           ← マッチ開始
=== Critical response === ← 含まれる
=== Box office ===        ← 含まれる
== Legacy ==              ← マッチ終了（次のLevel 2見出し）
```

### セクション境界

- セクションは次の**同レベル以上**の見出しで終了
- `== A ==` の後に `== B ==` が来たら `A` は終了
- `== A ==` の後に `=== A.1 ===` が来ても `A` は継続

---

## 7. フィルタリングオプション

### 7.1 最小文字数フィルタ

```bash
--min-section-length N   # N文字未満のセクションを除外
```

**用途:** 短すぎるセクション（スタブ等）を除外してコーパス品質を向上

**動作:**

```json
// --min-section-length 100 の場合
{
  "title": "Example Article",
  "sections": {
    "summary": "This is a long enough summary that exceeds 100 characters...",
    "Plot": "This is a substantial plot section with enough content...",
    "Reception": null  // 50文字しかなかったため除外（nullとして出力）
  }
}
```

### 7.2 サンプリング（将来的なオプション）

```bash
--sample N              # ランダムにN件の記事を抽出
--sample-per-section N  # 各セクションタイプごとにN件抽出
```

---

## 8. メタデータ抽出・統計出力

### 8.1 メタデータ抽出モード（`--category-only` の拡張）

既存の `--category-only` を拡張し、セクション見出しも抽出可能にする。

```bash
# 既存: タイトル + カテゴリのみ
wp2txt --category-only

# 新規: タイトル + セクション見出し + カテゴリ
wp2txt --metadata-only
```

**出力形式（テキスト、TSV）:**

```
Title<TAB>Section1|Section2|Section3<TAB>Category1,Category2,Category3
```

**出力形式（JSON）:**

```json
{
  "title": "The Shawshank Redemption",
  "sections": ["Plot", "Cast", "Production", "Release", "Reception", "Accolades", "Legacy"],
  "categories": ["1994 films", "American drama films", "Prison films"]
}
```

**用途:**
- Wikipedia全体のセクション名分布を調査
- エイリアス候補の発見
- コーパス設計の事前調査

### 8.2 セクション統計モード

```bash
--section-stats         # セクションの出現統計を集計
```

**出力例:**

```json
{
  "total_articles": 150000,
  "section_counts": {
    "Plot": 45000,
    "Synopsis": 12000,
    "Reception": 38000,
    "Critical reception": 8500,
    "Early life": 62000,
    "History": 55000,
    "Career": 58000,
    "Personal life": 42000
  },
  "top_sections": [
    {"name": "References", "count": 145000},
    {"name": "External links", "count": 140000},
    {"name": "Early life", "count": 62000},
    {"name": "Career", "count": 58000},
    {"name": "Plot", "count": 45000}
  ]
}
```

**用途:** セクション選択の定量的な根拠を得る

### 8.3 推奨ワークフロー

```
Step 1: メタデータ抽出（全記事）
┌─────────────────────────────────────────┐
│ wp2txt -i dump.xml.bz2 --metadata-only  │
│         --format json > metadata.jsonl  │
└─────────────────────────────────────────┘
        ↓
Step 2: セクション名の分布を分析
┌─────────────────────────────────────────┐
│ # Pythonやjqで集計                      │
│ cat metadata.jsonl | jq '.sections[]'  │
│     | sort | uniq -c | sort -rn        │
└─────────────────────────────────────────┘
        ↓
Step 3: 抽出対象セクションを決定
┌─────────────────────────────────────────┐
│ # 上位セクションから選択                │
│ Plot: 45000件                           │
│ Synopsis: 12000件 → Plotのエイリアス？  │
│ Reception: 38000件                      │
│ Critical reception: 8500件 → エイリアス │
└─────────────────────────────────────────┘
        ↓
Step 4: 選択的抽出を実行
┌─────────────────────────────────────────┐
│ wp2txt --sections "summary,Plot,..."    │
│         --alias-file custom.yml         │
└─────────────────────────────────────────┘
```

---

## 9. エッジケース

### 記事にセクションがない場合

```json
{
  "title": "Short Article",
  "sections": {
    "summary": "This is a stub article with no sections."
  },
  "categories": ["Stubs"]
}
```

### サマリーが存在しない場合

まれだが、記事が見出しから始まる場合：

```json
{
  "title": "Unusual Article",
  "sections": {
    "summary": null,
    "Plot": "The story begins..."
  }
}
```

### リダイレクト記事

- `--redirect` フラグと組み合わせ可能
- セクション抽出はリダイレクト先では行わない（タイトルのみ）

```json
{
  "title": "Redirect Article",
  "redirect": "Target Article",
  "sections": {}
}
```

### 同名セクションが複数ある場合

```
== Career ==
=== Early career ===
=== Later career ===
== Career ==  ← 2つ目の "Career"
```

対応方針: **最初のマッチのみ抽出**（将来的に `--section-all` で全て抽出も検討）

### 指定セクションが全て存在しない記事

`--skip-empty` フラグで出力をスキップ可能：

```bash
# 指定セクションが1つも見つからない記事を出力しない
wp2txt --sections "Plot,Reception" --skip-empty
```

---

## 10. 実装ノート

### Article クラスの変更

```ruby
# 現在
[:mw_heading, "Plot"]

# 拡張後
[:mw_heading, "Plot", 2]  # 第3要素にレベル（=の数）
```

### セクション抽出ロジック（疑似コード）

```ruby
def extract_sections(elements, target_sections, aliases = {})
  result = {}
  current_section = nil
  current_level = nil
  buffer = []

  # サマリー抽出（最初の見出しまで）
  if target_sections.include?("summary")
    result["summary"] = extract_summary(elements)
  end

  elements.each do |type, content, level|
    if type == :mw_heading
      # 前のセクションを保存
      if current_section
        canonical = find_canonical_name(current_section, target_sections, aliases)
        result[canonical] = buffer.join("\n") if canonical
      end

      # 新しいセクションを開始
      canonical = find_canonical_name(content, target_sections, aliases)
      if canonical
        current_section = content
        current_level = level
        buffer = []
      elsif current_level && level <= current_level
        # 同レベル以上の見出しでセクション終了
        current_section = nil
        current_level = nil
      end
    elsif current_section
      buffer << content
    end
  end

  # 最後のセクションを保存
  if current_section
    canonical = find_canonical_name(current_section, target_sections, aliases)
    result[canonical] = buffer.join("\n") if canonical
  end

  result
end

def find_canonical_name(heading, targets, aliases)
  # 直接マッチ
  targets.each do |t|
    return t if t.downcase == heading.downcase
  end
  # エイリアスマッチ
  aliases.each do |canonical, alias_list|
    if targets.include?(canonical) && alias_list.any? { |a| a.downcase == heading.downcase }
      return canonical
    end
  end
  nil
end
```

---

## 11. テストケース

### 基本動作: サマリー + セクション

```bash
# 入力: Plotセクションを持つ映画記事
wp2txt --sections "summary,Plot" --format json

# 期待出力:
{
  "title": "Inception",
  "sections": {
    "summary": "Inception is a 2010 science fiction...",
    "Plot": "Dom Cobb is a skilled thief..."
  },
  "categories": [...]
}
```

### セクションのみ（サマリーなし）

```bash
wp2txt --sections "Plot,Reception" --format json

# 期待出力:
{
  "title": "Inception",
  "sections": {
    "Plot": "Dom Cobb is a skilled thief...",
    "Reception": "The film received critical acclaim..."
  },
  "categories": [...]
}
```

### 存在しないセクション

```bash
# 入力: Plotセクションがない人物記事
wp2txt --sections "summary,Plot,Early life" --format json

# 期待出力:
{
  "title": "Albert Einstein",
  "sections": {
    "summary": "Albert Einstein was a German-born theoretical physicist...",
    "Plot": null,
    "Early life": "Einstein was born..."
  },
  "categories": [...]
}
```

### エイリアスによるマッチ

```bash
# 記事に "Synopsis" セクションがある場合
wp2txt --sections "summary,Plot" --section-aliases --format json

# 期待出力（"Synopsis" が "Plot" として出力）:
{
  "title": "Some Movie",
  "sections": {
    "summary": "...",
    "Plot": "The story follows..."  // 実際は "Synopsis" にマッチ
  },
  "matched_sections": {
    "Plot": "Synopsis"
  }
}
```

### Combined モード

```bash
wp2txt --sections "summary,Plot" --section-output combined --format json

# 期待出力:
{
  "title": "Inception",
  "text": "Inception is a 2010 science fiction...\n\nDom Cobb is a skilled thief...",
  "sections_included": ["summary", "Plot"],
  "categories": [...]
}
```

---

## 12. 今後の拡張可能性

1. **正規表現マッチング**: `--section-match regex` + `--sections "/^(Plot|Synopsis)$/i"`
2. **多言語セクション名**: 日本語「あらすじ」、ドイツ語「Handlung」等のマッピング
3. **セクションレベル指定**: `--section-level 2` でLevel 2見出しのみ
4. **サンプリング**: `--sample N` でランダム抽出
5. **並列処理との統合**: 大規模ダンプ処理時のパフォーマンス最適化

---

## 13. CLIフラグまとめ

### セクション抽出関連

| フラグ | 短縮 | デフォルト | 説明 |
|--------|------|-----------|------|
| `--sections NAMES` | `-S` | - | 抽出するセクション（カンマ区切り、`summary`含む） |
| `--section-output MODE` | - | `structured` | 出力モード: `structured` / `combined` |
| `--no-section-aliases` | - | - | エイリアスマッチングを無効化 |
| `--alias-file FILE` | - | - | カスタムエイリアス定義ファイル（YAML） |
| `--min-section-length N` | - | 0 | 最小文字数フィルタ |
| `--skip-empty` | - | 無効 | 該当セクションがない記事をスキップ |

### メタデータ・統計関連

| フラグ | 短縮 | デフォルト | 説明 |
|--------|------|-----------|------|
| `--category-only` | `-g` | - | タイトル + カテゴリのみ（既存） |
| `--metadata-only` | `-M` | - | タイトル + セクション見出し + カテゴリ（新規） |
| `--section-stats` | - | - | セクション出現統計を集計 |

### 大文字小文字の扱い

- `summary` を含む全てのセクション名は **case-insensitive**（大文字小文字を区別しない）
- `--sections "Summary,PLOT,reception"` → 正常に動作

---

## 14. 関連ドキュメント

- EngTagger 2.0プロジェクト計画書: `engtagger/ENGTAGGER_V2_PROJECT.md`
- wp2txt README: `wp2txt/README.md`
