## Why

`rails-app-scaffold` gave the project a `web`/`worker` codebase with no application code yet — the app doesn't know what an Ansible module is, has no database schema for it, and has no way to populate one. This change delivers the first real capability: `worker` fetching `ansible.builtin` module docs, chunking them, embedding them via the `embedder` sidecar, and storing them in Postgres. Without this, nothing downstream (retrieval, the chat agent, evaluation) has any data to work against.

## What Changes

- Add `ansible_modules` and `chunks` tables (migrations), with `chunks.embedding` as `vector(384)` (`neighbor`/`pgvector` gems) and `chunks.search_text` as a generated `tsvector` column with a GIN index.
- Add `AnsibleModule` and `Chunk` ActiveRecord models.
- Add `AnsibleDocClient` — shells out to `ansible-doc --list` / `ansible-doc -j` via `Open3`, also capturing `ansible-doc --version`.
- Add `Ingestion::Chunker` — turns one module's raw `ansible-doc -j` output into `overview` / `parameter` / `example` / `return` chunks, per the granularity validated in design.md.
- Add `EmbeddingClient` — Faraday-based HTTP client calling the `embedder` sidecar's `POST /embed`, order-preserving.
- Add `IngestAnsibleModulesJob` — a Solid Queue recurring job (`config/recurring.yml`) that runs the full fetch → chunk → embed → wipe-and-reload sequence inside one DB transaction.
- Add `faraday`, `faraday-retry`, `neighbor`, `pgvector` gems to `rails_app/Gemfile`.

Not in scope: keyword/vector/hybrid retrieval, the chat agent, the UI, or evaluation tooling — those are later slices per `PLAN.md`'s build order and depend on this change's schema/data existing first.

## Capabilities

### New Capabilities
- `ansible-ingestion`: fetching `ansible.builtin` module docs via `ansible-doc`, chunking them into retrievable units, embedding them via the `embedder` sidecar, and persisting them with full-text + vector search columns, on a recurring schedule with atomic wipe-and-reload semantics.

### Modified Capabilities
(none — this change only adds new tables/code on top of `rails-app` and `postgres-database`'s existing guarantees; neither capability's own requirements change)

## Impact

- **New**: `rails_app/db/migrate/*_create_ansible_modules.rb`, `*_create_chunks.rb`; `app/models/ansible_module.rb`, `app/models/chunk.rb`; `app/services/ansible_doc_client.rb`, `app/services/embedding_client.rb`, `app/services/ingestion/chunker.rb`; `app/jobs/ingest_ansible_modules_job.rb`; `config/recurring.yml` entry.
- **Modified**: `rails_app/Gemfile`/`Gemfile.lock` (new gems), `rails_app/db/schema.rb` (via migrations).
- **Depends on**: `embedder` service's existing `/embed` contract (already specified in `embedding-service`), `postgres-database`'s existing `pgvector`/`tsvector` support, `worker`'s existing `ansible-core` install (all already delivered by prior changes).
- **No changes to**: `web` image, `docker-compose.yml` service definitions, `embedder/`.
