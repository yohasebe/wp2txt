# wp2txt 改善計画

## 現状分析 (2026-01-09)

| 指標 | 値 |
|------|-----|
| テストカバレッジ | 77.38% |
| 総メソッド数 | 209 |
| 正規表現操作 | 197箇所 |
| 広範な例外処理 | 9箇所 |

---

## Phase 1: 保守性 (コード構造改善)

### 1.1 utils.rb の分割 (1024行 → 7ファイル)

| 新ファイル | メソッド | 行数目安 |
|-----------|---------|---------|
| `character_utils.rb` | convert_characters, special_chr, chrref_to_utf, mndash | ~80 |
| `marker_utils.rb` | marker_placeholder, finalize_markers, apply_markers, replace_*_with_marker, MARKER_* | ~200 |
| `nested_structure.rb` | process_nested_structure, process_nested_single_pass, escape/unescape_nowiki | ~100 |
| `link_utils.rb` | process_interwiki_links, apply_pipe_trick, process_external_links | ~80 |
| `template_utils.rb` | correct_inline_template, extract_template_content, format_citation, template_matches? | ~200 |
| `cleanup_utils.rb` | cleanup, remove_*, make_reference | ~150 |
| `file_utils.rb` | collect_files, file_mod, batch_file_mod, rename, sec_to_str | ~80 |
| `utils.rb` (残り) | format_wiki, parse_markers_config + require文 | ~100 |

### 1.2 bin/wp2txt の分割 (1011行)
- [ ] `lib/wp2txt/commands/convert.rb` - 変換処理
- [ ] `lib/wp2txt/commands/extract.rb` - 抽出処理
- [ ] `lib/wp2txt/commands/category.rb` - カテゴリ抽出

### 1.3 multistream.rb (775行)
- [x] スキップ: 4クラス平均190行で適切、分割不要

---

## Phase 2: 安定性

### 2.1 例外処理の改善
- [x] 14箇所の `rescue StandardError` を具体的な例外クラスに置換
- [x] カスタム例外クラスの定義 (`Wp2txt::Error`, `Wp2txt::ParseError`, `Wp2txt::NetworkError`, etc.)

### 2.2 テストカバレッジ向上 (77% → 90%)
- [ ] bin/wp2txt のユニットテスト追加
- [ ] エッジケーステスト（破損ファイル、巨大ファイル、不正エンコーディング）
- [ ] 統合テストの追加

### 2.3 入力バリデーション強化
- [ ] bz2ファイル破損検出
- [ ] メモリ使用量監視とgraceful degradation

---

## Phase 3: 速度

### 3.1 正規表現の最適化
- [ ] 頻繁に使用されるパターンの事前コンパイル確認
- [ ] 複数gsub連鎖の統合（1パス処理）
- [ ] ベンチマークスクリプト作成

### 3.2 ストリーミング処理改善
- [ ] メモリ使用量プロファイリング
- [ ] バッファサイズ動的調整

### 3.3 並列処理強化
- [ ] `--from-category` 記事抽出の並列化
- [ ] インデックス解析の高速化

---

## 進捗記録

| 日付 | Phase | 項目 | 状態 |
|------|-------|------|------|
| 2026-01-09 | 1.1 | utils.rb を3ファイルに分割 (1024行→656行) | 完了 |
| 2026-01-09 | 1.2 | bin/wp2txt を3ファイルに分割 (1011行→360行) | 完了 |
| 2026-01-09 | 2.2 | テストカバレッジ向上 (77.38%→83.81%, 562→690テスト) | 進行中 |
| 2026-01-09 | 2.1 | 例外処理の改善 (14箇所のrescue StandardError→具体的な例外) | 完了 |
