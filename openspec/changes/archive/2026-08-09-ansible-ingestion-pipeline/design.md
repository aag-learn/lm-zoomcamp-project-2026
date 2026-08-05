## Context

`rails_app/` currently has no application code — no models, no migrations, no `db/schema.rb`. `postgres-database` guarantees the `pgvector` extension and `tsvector`/GIN support are *available*, but nothing has enabled or used them yet; this change's first migration is what actually runs `CREATE EXTENSION vector`. `embedding-service` already specifies and implements the sidecar's `POST /embed` contract (order-preserving, empty-list-safe, 384-dim vectors from `all-MiniLM-L6-v2`) — this change is the first real consumer of it. `rails-app` already confirmed `worker` has `ansible-core` installed and that `web` never runs Solid Queue jobs in-process (`SOLID_QUEUE_IN_PUMA` is unset in `docker-compose.yml`), so ingestion code is safe to live in the shared codebase without a runtime guard even though `web` never calls it.

The chunking granularity decisions below were validated against real `ansible-doc -j` output pulled directly from all 71 modules in the `ansible.builtin` collection (via the locally installed `ansible-doc [core 2.21.2]`), and against the actual cached `all-MiniLM-L6-v2` model config — not assumed from `PLAN.md` alone.

## Goals / Non-Goals

**Goals:**
- Get real, queryable, embedded documentation into Postgres for all 71 `ansible.builtin` modules.
- Fix a discovered defect in `PLAN.md`'s original chunking granularity (see Decisions) before it ships, not after eval surfaces it.
- Keep the wipe-and-reload run atomic and cheap enough that "no incremental update logic" remains the right call.

**Non-Goals:**
- Retrieval (keyword/vector/hybrid search) — schema is shaped to support it (see `search_text`/`embedding` columns) but no query-side code ships here.
- The `get_module_details` agent tool — `AnsibleModule.raw_doc` is stored specifically so that tool can be built later without a second `ansible-doc` fetch, but the tool itself isn't built in this change.
- Collections beyond `ansible.builtin`.

## Decisions

**`chunk_type` is a plain string column, not a Rails `enum`.** An integer-backed enum is marginally smaller and gives free `Chunk.parameter` scopes, but this project's eval work (retrieval-eval rake task, ground-truth generation) involves a lot of ad-hoc `psql` inspection of the `chunks` table by hand. A string column shows `"parameter"` directly in query output; an enum shows an opaque integer unless you remember or look up the mapping. Optimizing for that debugging path over a marginal storage/ergonomics win.

**`ansible_core_version` is denormalized onto `Chunk`, not only `AnsibleModule`.** Every retrieval result is a `Chunk` row, and provenance ("this answer used ansible-core 2.17 docs") needs to travel with what's actually returned to the LLM/UI without a join back to `AnsibleModule` on every retrieval call. The cost is trivial — one wipe-and-reload writes the same version string onto every row in a run.

**Skip the `pg_search` gem; use a raw SQL scope for full-text search.** The generated `tsvector` column (`chunks.search_text`) and its GIN index have to be hand-written in the migration regardless — `pg_search` doesn't manage generated columns for you. Given that, its incremental value over a small `Chunk` class method wrapping `to_tsvector`/`plainto_tsquery`/`ts_rank` is low, and raw SQL keeps the later hybrid-search RRF merge (which needs raw rank numbers back from both the keyword and vector paths) more direct.

**Chunk granularity, validated against real data:**

| Chunk type | Granularity | Evidence |
|---|---|---|
| `overview` | 1 per module | 71 total |
| `parameter` | 1 per top-level option (suboptions flattened in) | 818 total across 71 modules, median 8/module, max 58 (`yum_repository`) |
| `example` | 1 per named example (top-level YAML list item), **not** 1 per module | 472 total across 71 modules; examples block ranges 146–4041 chars (median 990); see truncation finding below |
| `return` | 1 per return value, **not** 1 combined block/module | 177 total across 71 modules |

**Measured total: 1,538 chunks**, all with unique `stable_id`s — verified by running the real `Ingestion::Chunker` against real `ansible-doc -j` output for all 71 `ansible.builtin` modules during implementation, not just estimated. This revises `PLAN.md`'s "~1,000-1,400" figure upward, specifically because of the `example` granularity change below: `PLAN.md`'s estimate assumed 1 example chunk/module (~71), but the real per-named-example count is 472 — a direct, expected consequence of fixing the truncation bug, not a discrepancy to chase.

**Why `example` chunking changed from `PLAN.md`'s 1-per-module to 1-per-named-example — a real discovered defect, not a restatement.** The bi-encoder's own cached config (`sentence_bert_config.json`) confirms `max_seq_length: 256` word-pieces; `SentenceTransformer.encode()` truncates silently past that with no warning. The longest real `examples` block (`ansible.builtin.uri`, 4041 chars) is roughly 3-4x the model's effective capacity — under the original 1-chunk/module design, that module's examples chunk would be embedded on only its first quarter, with no error surfaced anywhere. Splitting on top-level named-example boundaries fixes this because individual examples are naturally short (the 4041-char block is itself made of several ~500-800 char examples) and gives examples the same per-field granularity as parameters/returns.

**Why `return` chunking is 1-per-value, not 1-per-module.** `PLAN.md` only specified a stable-ID pattern for parameters (`{fqcn}::param::{name}`) and left `return` ambiguous. Resolved for symmetry with `parameter`: a single-fact retrieval question ("what does `copy` return in `backup_file`") deserves a single-fact chunk, and it keeps chunking and later retrieval-eval ground-truth generation using one shared "per-field" code shape for both types instead of two different ones.

**Nested `suboptions` are flattened into the parent parameter's chunk text, not given their own recursive chunk-ID scheme.** Across all 820 options in the collection, exactly one — `ansible.builtin.iptables`'s `tcp_flags` — has `suboptions`. Building general recursive handling for a single occurrence isn't worth the complexity; its sub-fields are folded into `tcp_flags`'s own chunk content as additional text.

**Stable IDs**: `{fqcn}::overview`, `{fqcn}::param::{name}`, `{fqcn}::example::{n}` (1-based index within the module), `{fqcn}::return::{name}`.

**`ansible-doc` invocation uses `Open3.capture2`/`capture3`, not backticks or `system`.** Need real exit-status checking (to satisfy the "fetch failure aborts without touching existing data" requirement) and a separate capture of `ansible-doc --version` for the version tag — `Open3` gives both without shelling through `/bin/sh`.

**Embedder HTTP client uses Faraday + `faraday-retry`, not stdlib `Net::HTTP` or HTTParty.** `Net::HTTP` would match the "use what's already in the image" philosophy documented in `CLAUDE.md` for service healthchecks, but that philosophy is specifically about not adding a new binary to a container just for a one-line liveness check. This is a different category: a real batched RPC client used both during a long-running ingestion run and at live chat query time later, where a transient hiccup (the `embedder` sidecar mid-restart during a deploy) is exactly what retry-with-backoff middleware exists for. Faraday is also the established Rails-ecosystem client for typed service objects (`EmbeddingClient`, and later `RerankerClient`).

## Risks / Trade-offs

- **Faraday retry could mask a genuinely broken embedder as a slow-but-working one.** → Bound the retry count and backoff explicitly (not unlimited); a persistently failing embedder should still surface as a job failure, triggering the transaction rollback rather than silently retrying forever.
- **Splitting `examples` assumes the YAML blob parses as a list of named top-level items.** Real `ansible.builtin` data confirms this holds today, but it's a parse assumption, not a schema guarantee from `ansible-doc`. → Parse defensively; if the block doesn't parse as a list (or fails to parse at all), fall back to storing it as a single `example` chunk rather than raising and aborting the whole module.
- **Flattening `iptables`'s `tcp_flags` suboptions loses independent queryability for that one nested field** (e.g. a question specifically about `tcp_flags.flags_set` retrieves the whole `tcp_flags` chunk, not a smaller one). → Acceptable given it's 1 of 820 options; revisit only if retrieval eval specifically shows a gap there.
- **Full wipe-and-reload on every run** is already an accepted trade-off from `PLAN.md`'s ingestion design (not reopened here) — cheap at this data size (1,538 chunks, local CPU embedding, no per-call dollar cost).

## Migration Plan

1. Migration: `enable_extension "vector"` (first use of `pgvector` in this project — `postgres-database` guaranteed availability, this change is what actually turns it on).
2. Migration: create `ansible_modules` (fqcn, description, deprecated, raw_doc jsonb).
3. Migration: create `chunks` (belongs_to ansible_module, chunk_type string, stable_id, content, generated `search_text` tsvector + GIN index, `embedding` vector(384), ansible_core_version), with a unique index on `stable_id`.
4. Add gems (`faraday`, `faraday-retry`, `neighbor`, `pgvector`) to `rails_app/Gemfile`, `bundle install`.
5. No rollback complexity beyond standard Rails migration rollback — this is additive (new tables), nothing existing is altered.

## Resolved: bulk insert mechanism

Chosen: **`insert_all`**, not `Chunk.create!` in a loop. The premise for deferring this — that `create!` earns its keep via AR validation coverage (e.g. embedding-dimension checks) — turned out not to hold once checked directly: `vector(384)` is a *typed* pgvector column, and Postgres itself rejects a wrong-dimension vector at insert time (verified directly: inserting a 10-dimension vector into the column raises `ERROR: expected 384 dimensions, not 10`, no AR validation needed). Combined with the schema's existing `NOT NULL` constraints and the unique index on `stable_id`, the database already enforces every invariant this change's spec cares about (every chunk has an embedding, every chunk has a unique stable ID) — `create!`'s validation coverage would be redundant, not protective. `insert_all` is faster and matches the wipe-and-reload run's existing bulk `delete_all` operations.

## Resolved: `/embed` batch size

Measured directly against a running `embedder` instance with the real, complete chunk set (1,538 texts, 415KB total JSON payload) rather than guessed:

| Batch size | Requests | Total time |
|---|---|---|
| 50 | 31 | 34.8s |
| 100 | 16 | 26.5s |
| 250 | 7 | 21.2s |
| 500 | 4 | 20.0s |
| 1,538 (single request) | 1 | 18.6s |

Fewer, larger requests are consistently faster — per-request overhead dominates more than encode-batch efficiency at this data size, and the whole payload (415KB) is trivially small for a single HTTP request regardless. A single giant request would be marginally fastest, but batching at **500** is chosen instead: within ~7% of the single-request time, while keeping individual request bodies modest (~130KB) and giving partial-progress visibility — if one batch's request fails after exhausting `EmbeddingClient`'s retries, the job fails having only wasted the other 3 batches' worth of redundant re-work on its next run, not the whole set. This batching decision lives in `IngestAnsibleModulesJob` (the orchestration layer), not inside `EmbeddingClient` itself — the client stays a simple "embed exactly what you give it" HTTP wrapper.
