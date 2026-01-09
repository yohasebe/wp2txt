# wp2txt Improvement Plan

## Initial Analysis (2026-01-09)

| Metric | Value |
|--------|-------|
| Test Coverage | 77.38% |
| Total Methods | 209 |
| Regex Operations | 197 |
| Broad Exception Handling | 9 places |

---

## Phase 1: Maintainability (Code Structure)

### 1.1 Split utils.rb (1024 lines)

| New File | Methods | Est. Lines |
|----------|---------|------------|
| `character_utils.rb` | convert_characters, special_chr, chrref_to_utf, mndash | ~80 |
| `marker_utils.rb` | marker_placeholder, finalize_markers, apply_markers, replace_*_with_marker, MARKER_* | ~200 |
| `nested_structure.rb` | process_nested_structure, process_nested_single_pass, escape/unescape_nowiki | ~100 |
| `link_utils.rb` | process_interwiki_links, apply_pipe_trick, process_external_links | ~80 |
| `template_utils.rb` | correct_inline_template, extract_template_content, format_citation, template_matches? | ~200 |
| `cleanup_utils.rb` | cleanup, remove_*, make_reference | ~150 |
| `file_utils.rb` | collect_files, file_mod, batch_file_mod, rename, sec_to_str | ~80 |
| `utils.rb` (remaining) | format_wiki, parse_markers_config + require statements | ~100 |

### 1.2 Split bin/wp2txt (1011 lines)
- [ ] `lib/wp2txt/commands/convert.rb` - Conversion processing
- [ ] `lib/wp2txt/commands/extract.rb` - Extraction processing
- [ ] `lib/wp2txt/commands/category.rb` - Category extraction

### 1.3 multistream.rb (775 lines)
- [x] Skip: 4 classes averaging 190 lines each, appropriate structure

---

## Phase 2: Stability

### 2.1 Exception Handling Improvement
- [x] Replace 14 `rescue StandardError` with specific exception classes
- [x] Define custom exception classes (`Wp2txt::Error`, `Wp2txt::ParseError`, `Wp2txt::NetworkError`, etc.)

### 2.2 Test Coverage Improvement (77% -> 90%)
- [x] Add tests for core modules (utils, multistream, stream_processor)
- [ ] Add unit tests for bin/wp2txt
- [ ] Add edge case tests (corrupted files, large files, invalid encoding)
- [ ] Add integration tests

### 2.3 Input Validation Enhancement
- [ ] bz2 file corruption detection
- [ ] Memory usage monitoring and graceful degradation

---

## Phase 3: Performance

### 3.1 Regex Optimization
- [ ] Verify pre-compilation of frequently used patterns
- [ ] Consolidate multiple gsub chains (single-pass processing)
- [ ] Create benchmark scripts

### 3.2 Streaming Processing Improvement
- [ ] Memory usage profiling
- [ ] Dynamic buffer size adjustment

### 3.3 Parallel Processing Enhancement
- [ ] Parallelize `--from-category` article extraction
- [ ] Optimize index parsing

---

## Progress Log

| Date | Phase | Item | Status |
|------|-------|------|--------|
| 2026-01-09 | 1.1 | Split utils.rb into 3 files (1024 -> 656 lines) | Done |
| 2026-01-09 | 1.2 | Split bin/wp2txt into 3 files (1011 -> 360 lines) | Done |
| 2026-01-09 | 2.1 | Exception handling (14 rescue StandardError -> specific) | Done |
| 2026-01-09 | 2.2 | Test coverage (77.38% -> 84.68%, 562 -> 717 tests) | Done |
