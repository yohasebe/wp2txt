# Offline Indexes, Queries, and the MCP Server

This guide covers wp2txt's index-based features: local indexes over Wikipedia dumps,
offline queries across a whole edition, full-text search, interlanguage links,
cross-language SQL, and the MCP server for connecting an LLM client.

For plain-text extraction (the classic wp2txt), see the [README](../README.md).

Everything below runs against a downloaded dump file: queries cover every article of the
edition rather than a page of search results, results are tied to one dump (e.g.
`jawiki-20260701`) and can be reproduced later, and nothing goes over the network once
the dump is downloaded. Typical uses: "which of the 1.5M articles have a plot section",
"how many film articles mention X, and which ones don't", "how do the section structures
of the same article differ between the English and Japanese editions".

## 1. Building the indexes

```console
# Metadata index (categories, section headings, redirects, category hierarchy)
$ wp2txt --build-index --lang=ja

# Metadata index + FTS5 full-text index over the cleaned article text
$ wp2txt --build-index --fulltext --lang=ja
```

The dump is downloaded automatically if needed and everything is cached under
`~/.wp2txt/cache/`. Ballpark figures (Apple Silicon laptop): Japanese Wikipedia ~15 min /
~1.7 GB for the metadata index, ~1.5 h / ~12 GB with full text; English roughly 2.5–3× the
time, ~10 GB / ~12 GB respectively.

The full-text tokenizer is selected per language: character trigrams for Japanese,
Chinese, and Korean; word-based (`unicode61`, no stemming) for space-delimited languages.
The choice is recorded in the index metadata.

Indexes are rebuilt atomically (a failed rebuild never destroys the working index), and
each index records the wp2txt version that built it — `dump_info` can flag indexes whose
text-cleaning code differs from the running version.

## 2. Exhaustive queries from the CLI

```console
# All film articles (recursing 3 subcategory levels) that have a plot section
$ wp2txt --find-articles --in-category "映画作品" -D 3 --has-section "あらすじ" --lang=ja

# Machine-readable output with total count
$ wp2txt --find-articles --in-category "Films" -D 2 -j json --limit 100 --lang=en

# Full-text search composed with metadata filters
$ wp2txt --search "タイムループ" --in-category "映画作品" -D 3 --lang=ja
```

Search totals count every match in the edition, so `0 matches` means the term is absent
from that dump version — a result you can state and re-verify later.

## 3. Interlanguage links (langlinks)

Import the official `langlinks` dump into the metadata index to map articles across
language editions:

```console
$ wp2txt --import-langlinks -L ja --langlinks-langs en,de,fr,zh,ko
```

- **Version pinning is enforced**: the langlinks file must carry the same dump date as
  the built index; a mismatch is rejected with no override.
- Import provenance (source file, time, tool version, row count, rows skipped for
  invalid encoding) is stamped into the index and reported by `dump_info`.
- A post-import sanity check joins a per-language sample against locally installed
  editions and reports the match rate.

This adds a `langlinks` table (`ll_from` = source page_id, `ll_lang`, `ll_title`) that can
be joined in SQL. Tip: filter `ll_title != ''` — real dumps contain a few empty-title rows.

## 4. The MCP server

`wp2txt-mcp` exposes a local dump to any MCP-capable LLM client (Claude, ChatGPT, Gemini,
local models):

```console
$ gem install mcp                    # optional dependency, needed only for the server
$ wp2txt --build-index --lang=ja     # prerequisite
$ wp2txt-mcp --lang=ja               # stdio MCP server
```

Example client configuration (e.g., Claude Desktop / Claude Code):

```json
{
  "mcpServers": {
    "wp2txt": { "command": "wp2txt-mcp", "args": ["--lang", "ja"] }
  }
}
```

Or run everything from the container image (no Ruby required on the host):

```console
$ docker run -it -v wp2txt:/root/.wp2txt ghcr.io/yohasebe/wp2txt wp2txt --build-index --fulltext -L ja
$ claude mcp add wp2txt -- docker run -i --rm -v wp2txt:/root/.wp2txt ghcr.io/yohasebe/wp2txt wp2txt-mcp -L ja
```

(Use `-i`, not `-it`, for the MCP server — a TTY would corrupt the JSON-RPC stream.)

### Tools

| Tool | Purpose |
|------|---------|
| `dump_info` | Dump identity, installed indexes, corpus statistics, langlinks provenance |
| `get_article` / `get_sections` / `list_headings` / `get_categories` | Single-article access (redirect-aware) |
| `find_articles` | Exhaustive filtered listing (category recursion, category AND / pattern match, section headings, title match) |
| `category_tree` / `section_stats` | Scope exploration and heading-frequency discovery |
| `search_text` | Full-text search composed with metadata filters; exact or capped exhaustive counts |
| `query_sql` | Read-only SQL (SELECT/WITH) over the index databases — the escape hatch for queries the fixed tools cannot express; supports cross-language `attach` and file output |
| `describe_schema` | Table/column introspection for query_sql |
| `section_cooccurrence` | Verify section-alias hypotheses (synonymous headings rarely co-occur in one article) |
| `save_alias_set` / `get_alias_set` / `list_alias_sets` | Persist verified per-dump alias groups (server-side co-occurrence guardrail) |
| `extract_corpus` | Filtered or explicit-title extraction to JSONL + reproducibility sidecar; optional RAG chunking |
| `start_extract_job` / `job_status` / `cancel_job` / `list_jobs` | Background jobs for large extractions |

### What happens when your assistant uses these tools

- **Filtering and counting run over the whole dump**, and your assistant reads the result
  rather than tallying articles itself.
- **Large results are written to a file**; the reply carries a summary and a short sample.
  Your corpus lands on disk intact instead of being paraphrased through the chat.
- **Extractions are traceable.** Extractions and file-writing queries leave a `.meta.json`
  next to the output recording the dump version, the query, and any alias sets used, so
  you can reproduce or cite the result later.
- **The tools cannot change your data.** Queries run read-only and are stopped after 30
  seconds, saved alias sets are re-checked before being stored, and files can only be
  written under the server's output directory — worth knowing if you plan to let an
  assistant work unattended.

## 5. Cross-language SQL

With more than one language installed, `query_sql` can ATTACH other editions read-only:

```
query_sql(
  attach: ["en"],
  sql: "SELECT p.title AS ja_title, ll.ll_title AS en_title,
               (SELECT COUNT(*) FROM page_sections s WHERE s.page_id = p.page_id) AS ja_secs,
               (SELECT COUNT(*) FROM en_meta.page_sections s2
                JOIN en_meta.pages p2 ON p2.page_id = s2.page_id
                WHERE p2.title = ll.ll_title) AS en_secs
        FROM pages p
        JOIN langlinks ll ON ll.ll_from = p.page_id AND ll.ll_lang = 'en'
        WHERE p.namespace = 0 AND p.redirect_to IS NULL AND ll.ll_title != ''"
)
```

Attached databases appear as `{lang}_meta` (and `{lang}_fts` when that language has a
full-text index) and share the main database's schema. You pass language codes, not paths,
and the SQL you write cannot attach anything itself. The response lists what was attached,
including each edition's dump name, and flags it when the dates differ.

This runs entirely offline against pinned dump versions, so a cross-edition comparison can
be re-run later and produce the same numbers.

## 6. Large results, explicit sets, and reproducibility

```
# Write ALL rows of a query to disk; receive a summary + 3-row sample
query_sql(sql: "...", attach: ["en"], output_path: "pairs_ja_en.jsonl")

# Extract an explicit article set (e.g., determined via query_sql)
extract_corpus(titles: ["東京物語", "羅生門", ...], content: "summary",
               output_path: "screen.jsonl")
```

- `query_sql` + `output_path` streams every row to JSONL (atomically — a partial file is
  never left behind) and writes a `.meta.json` sidecar recording the SQL, the dump
  versions of every attached edition, and row counts.
- `extract_corpus` + `titles:` accepts up to 10,000 explicit titles, resolves one
  redirect hop, and reports unmatched titles in `not_found` — closing the loop
  *SQL decides the set → the tool materializes it → the LLM reads it*.

## 7. Section alias sets

Section headings vary by article and by language ("Plot" vs "Synopsis"; 「あらすじ」 vs
「ストーリー」), and wp2txt ships no per-language dictionaries. Three tools manage named
groups of equivalent headings instead:

- `section_stats` lists the headings actually used in a scope, with counts.
- `section_cooccurrence` reports how often two headings appear in the same article.
  Headings that mean the same thing rarely co-occur, so a high ratio is evidence that
  they are *different* sections (「概要」 and 「あらすじ」 co-occur often — not synonyms).
- `save_alias_set` stores a named group. The group is re-checked against co-occurrence
  before saving; a failing group is not stored and the call returns `saved: false`
  rather than an error. Pass `force` to override, and use `list_alias_sets` to see
  what is stored.

Queries then accept `alias_set: "name"` in place of a heading list, and extractions
record the group's exact contents in their `.meta.json`. The bundled `discover_aliases`
prompt walks an LLM client through building and saving a set.

## 8. Limitations to keep in mind

- Searches run over the **cleaned text**: content that extraction replaces with a marker
  (`[MATH]`, `[CODE]`, `[TABLE]`, …) cannot be matched. A count is a count of the cleaned
  text, not of the raw wikitext.
- Japanese, Chinese, and Korean indexes cannot match queries shorter than 3 characters.
  Word-based languages match exact forms only — `run` does not find `running`. Plan your
  search terms accordingly, especially when you intend to report a zero result.
- Categories and interlanguage links are read from the dump as editors wrote them.
  Categories added by a template rather than written in the article text are not visible
  to wp2txt, which can make a category look much smaller than it is on the website —
  check against the article text if a count looks wrong.
