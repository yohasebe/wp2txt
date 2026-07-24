# wp2txt Research Infrastructure Guide

This guide covers the research-oriented layer of wp2txt: local indexes over Wikipedia
dumps, exhaustive offline queries, full-text search, cross-language SQL, and the MCP
server that exposes all of this to LLM agents.

For plain-text extraction (the classic wp2txt), see the [README](../README.md).

## Concept

Web search and the Wikipedia API operate on ranked, paginated, ever-changing data. They
can show that something *exists*, but they cannot make **exhaustive** claims ("342 of the
11,486 film articles with a plot section mention X — and none of the others do"), and
their answers change from day to day.

wp2txt takes the opposite approach: build local indexes over an official dump file, so that
every query is

- **exhaustive** — it scans every article, not search-ranked results;
- **version-pinned** — results are tied to one dump (e.g. `jawiki-20260701`) and
  reproducible later;
- **agent-operable** — the MCP server exposes the whole layer to LLM agents, with
  guardrails and provenance records designed for autonomous use.

## 1. Building the indexes

```console
# Tier 1: metadata index (categories, section headings, redirects, category hierarchy)
$ wp2txt --build-index --lang=ja

# Tier 1 + Tier 2: add an FTS5 full-text index over the cleaned article text
$ wp2txt --build-index --fulltext --lang=ja
```

The dump is downloaded automatically if needed and everything is cached under
`~/.wp2txt/cache/`. Ballpark figures (Apple Silicon laptop): Japanese Wikipedia ~15 min /
~1.7 GB for the metadata index, ~1.5 h / ~12 GB with full text; English roughly 4× the
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

Search totals are exhaustive counts, so `0 matches` is a verifiable **absence claim** for
that dump version — something ranked web search cannot provide.

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
| `dump_info` | Dump identity, index tiers, corpus statistics, langlinks provenance |
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

### Design principles

- **Division of labor**: the tool does mechanical, exhaustive narrowing and counting;
  semantic judgment is left to the LLM. The LLM never has to count.
- **Context economy**: large results go to disk; the model receives a summary plus a
  3-record sample, never the full corpus.
- **Reproducibility**: every extraction and file-writing query records the dump version,
  the query, and any alias sets in a `.meta.json` sidecar.
- **Guardrails**: SQL is screened and executed read-only in a killable subprocess;
  alias sets are re-verified server-side before saving; output paths are confined to the
  server's output directory.

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
full-text tier) and share the main database's schema. Language codes are validated and
resolved server-side; user SQL can never contain ATTACH itself. The response records what
was attached (dump names included), and flags date mismatches between editions.

To the best of our knowledge no other system offers version-pinned, cross-edition SQL over
both metadata **and** article text, fully offline.

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

## 7. The alias discovery loop

Section headings vary ("Plot" vs "Synopsis"; 「あらすじ」 vs 「ストーリー」). wp2txt ships
no per-language dictionaries. Instead, agents discover aliases from the dump itself:

1. `section_stats` — find the actual headings used in a scope
2. LLM proposes synonym groups
3. `section_cooccurrence` — verify mechanically (true synonyms almost never co-occur in
   the same article; a high co-occurrence ratio is evidence *against* the hypothesis)
4. `save_alias_set` — persist the verified groups, re-checked server-side, and recorded
   in every extraction that uses them

The bundled `discover_aliases` MCP prompt walks any agent through this protocol.

## 8. Honest limitations

- Queries operate on the **cleaned-text space**: content replaced by markers
  (`[MATH]`, `[CODE]`, `[TABLE]`, …) is not searchable.
- Trigram languages (ja/zh/ko) cannot match queries shorter than 3 characters;
  word-based languages have no stemming (`run` ≠ `running`). Both are deliberate:
  exact counts and absence claims require predictable matching.
- Categories and links come from the dump itself, as written by editors — they inherit
  Wikipedia's own inconsistencies, which is precisely what makes them worth studying.
