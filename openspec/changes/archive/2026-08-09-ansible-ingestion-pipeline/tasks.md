## 1. Dependencies & schema

- [x] 1.1 Add `faraday`, `faraday-retry`, `neighbor`, `pgvector` gems to `rails_app/Gemfile`; add `webmock` to the `:test` group (per `CLAUDE.md`'s testing conventions — stub HTTP calls to `embedder` rather than hitting a real instance in tests); `bundle install`
- [x] 1.2 Migration: `enable_extension "vector"`
- [x] 1.3 Migration: create `ansible_modules` (fqcn, description, deprecated:boolean, raw_doc:jsonb), unique index on `fqcn`
- [x] 1.4 Migration: create `chunks` (belongs_to :ansible_module, chunk_type:string, stable_id:string, content:text, generated `search_text` tsvector column + GIN index, `embedding` vector(384) via neighbor, ansible_core_version:string), unique index on `stable_id`
- [x] 1.5 Run migrations against the dev stack; verify `rails_app/db/schema.rb` reflects both tables correctly
- [x] 1.6 Bump `rails_app/.github/workflows/ci.yml`'s `test` and `system-test` jobs' `postgres` service image from plain `postgres` to a pgvector-capable image (e.g. `pgvector/pgvector:pg18`, matching `docker-compose.yml`) — otherwise `enable_extension "vector"` (1.2) fails in CI

## 2. Models

- [x] 2.1 `AnsibleModule` model — `has_many :chunks`
- [x] 2.2 `Chunk` model — `belongs_to :ansible_module`, `has_neighbors :embedding` (neighbor gem), a class method/scope for full-text search over `search_text` (raw `to_tsvector`/`plainto_tsquery`/`ts_rank`, per design.md's decision to skip `pg_search`)
- [x] 2.3 Model tests: associations, and the full-text search scope against a couple of seeded rows

## 3. ansible-doc client — test-first (subprocess error handling is exactly the kind of logic CLAUDE.md's testing section calls out)

- [x] 3.1 Write `AnsibleDocClient` tests first (stubbing `Open3` or the subprocess boundary): successful fetch returns parsed docs + version, non-zero exit raises, unparseable output raises — before any implementation exists
- [x] 3.2 Implement `AnsibleDocClient` (`Open3.capture2`/`capture3`-based `ansible-doc --list ansible.builtin` then `ansible-doc -j <all names>`, plus a separate `ansible-doc --version` capture) to satisfy 3.1's tests

## 4. Chunker — test-first (this is the module where we already found one real bug; treat it as the highest-risk piece)

- [x] 4.1 Record real `ansible-doc -j` fixture files for a few modules chosen to exercise every edge case found during design: `copy` (baseline), `uri` (longest examples block — must split into multiple `example` chunks, not truncate), `iptables` (the one module with `suboptions`, on `tcp_flags` — must flatten, not drop)
- [x] 4.2 Write `Ingestion::Chunker` tests first, against those fixtures, covering: exactly 1 `overview` chunk/module; 1 `parameter` chunk per option with suboptions flattened into the parent's content; 1 `example` chunk per named example (confirm `uri` yields multiple, none truncated); 1 `return` chunk per return value; stable ID format for each type; the malformed/non-list `examples` YAML fallback (design.md's risk note) — before any implementation exists
- [x] 4.3 Implement the overview chunk builder
- [x] 4.4 Implement the parameter chunk builder (with suboption flattening)
- [x] 4.5 Implement the example chunk builder (YAML list parsing + per-example split + defensive fallback)
- [x] 4.6 Implement the return-value chunk builder
- [x] 4.7 Implement stable ID generation matching design.md's pattern: `{fqcn}::overview`, `{fqcn}::param::{name}`, `{fqcn}::example::{n}`, `{fqcn}::return::{name}`
- [x] 4.8 Run the full chunker against all fixtures from 4.1; confirm all of 4.2's tests pass (also verified against the real, complete 71-module `ansible.builtin` dataset: 1,538 chunks — 71 overview, 818 parameter, 472 example, 177 return — all unique `stable_id`s; see design.md's updated count)

## 5. Embedding client — test-first (HTTP failure/retry handling)

- [x] 5.1 Write `EmbeddingClient` tests first, using `webmock` to stub the `embedder`'s `/embed` endpoint: order-preservation, empty-input, and a retry-triggering transient failure followed by success — before any implementation exists
- [x] 5.2 Implement `EmbeddingClient` (Faraday connection with `faraday-retry` middleware, bounded retry count/backoff per design.md's risk mitigation, `POST /embed`) to satisfy 5.1's tests — discovered along the way that `faraday-retry`'s default `methods:` only covers idempotent verbs, so POST needed `methods: [:post]` explicitly or nothing would ever retry
- [x] 5.3 Prototype against the real 1,538-chunk volume from a full chunker run (4.8) to pick and hard-code an `/embed` batch size (resolves design.md's deferred open question) — measured 50/100/250/500/1538 against a live `embedder`; picked 500 (see design.md's "Resolved" section), implemented in `IngestAnsibleModulesJob`, not `EmbeddingClient`
- [x] 5.4 Decide and implement the bulk-insert mechanism for `Chunk` rows (`insert_all`/`upsert_all` vs `create!` in a loop) based on whether AR validation coverage (e.g. embedding dimension) is wanted (resolves design.md's other deferred open question) — decided `insert_all` after confirming empirically that Postgres's typed `vector(384)` column already rejects wrong-dimension vectors on its own (see design.md); implemented as part of 6.1

## 6. Ingestion job

- [x] 6.1 Implement `IngestAnsibleModulesJob` — orchestrates fetch (3) → chunk (4) → embed (5) → single DB transaction wipe-and-reload (`Chunk.delete_all` then `AnsibleModule.delete_all`, child-then-parent to satisfy the FK; then bulk insert via `insert_all!`), tagging every row with the run's `ansible-core` version. Fetch/chunk/embed all happen *before* the transaction opens, so a failure at any of those stages never touches the DB at all — a stronger and simpler guarantee than relying on rollback.
- [x] 6.2 Add a recurring schedule entry to `rails_app/config/recurring.yml` (weekly, per PLAN.md)
- [x] 6.3 Write a job test that stubs `AnsibleDocClient`/`EmbeddingClient` (no real `ansible-doc`/`embedder` needed) covering: a successful run fully replaces prior data with one consistent version tag, and an exception raised mid-run (both from a stubbed embedding-client failure and a stubbed fetch failure) leaves prior data untouched — this automates the transaction-boundary guarantee rather than relying only on manual verification

## 7. Verification (live-stack, end-to-end — complements the automated tests above, doesn't replace them)

- [x] 7.1 Run the job manually (`bin/rails runner 'IngestAnsibleModulesJob.perform_now'`) against the running `docker compose` stack; confirm `AnsibleModule.count == 71` — ran for real inside the actual built `worker` container (podman-compose), 71/71, ~17s
- [x] 7.2 Confirm `Chunk.count` is 1,538 and `Chunk.group(:chunk_type).count` matches the measured breakdown (71 overview, 818 parameter, 472 example, 177 return) — matched exactly
- [x] 7.3 Confirm every chunk has a non-null `embedding` and that `Chunk.distinct.pluck(:ansible_core_version)` shows exactly one version, matching `ansible-doc --version` output from the same run — 0 null embeddings, single version "2.21.2"
- [x] 7.4 Full-text search smoke test: a raw SQL query for a distinctive word returns the expected chunk — `Chunk.search("copy files remote")` returned `ansible.builtin.copy::overview` first
- [x] 7.5 Vector similarity smoke test: a `neighbor` nearest-neighbors query using an embedded test query returns a semantically relevant chunk — nearest neighbors to `copy`'s overview were `fetch`/`unarchive` (other file-transfer modules) and `copy`'s own examples — genuinely sensible, not just non-empty
- [x] 7.6 Atomicity check: kill the job process mid-run, confirm the previously stored module/chunk set is still intact and queryable afterward (not empty or partial) — `podman kill`'d the whole `worker` container ~3s into a real run (well before the transaction opens, since fetch/chunk/embed happen outside it); prior 71 modules / 1,538 chunks / single version were fully intact afterward
- [x] 7.7 Stable-ID check: run ingestion twice in a row, confirm a given module's given parameter chunk has the identical `stable_id` both times — `ansible.builtin.copy::param::mode` had the same `stable_id` across two real runs (surrogate row `id` changed as expected from the wipe-and-reload, `stable_id` did not)
