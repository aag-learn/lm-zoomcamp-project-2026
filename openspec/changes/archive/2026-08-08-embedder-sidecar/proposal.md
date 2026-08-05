## Why

The RAG pipeline needs embeddings for chunk text (produced by ingestion, later) and query text (produced live by retrieval, later), plus reranking scores for retrieval candidates — but no mature Ruby equivalent exists for `sentence-transformers`/`CrossEncoder` models, and neither OpenAI's embeddings API (extra cost/latency/network dependency) nor a fresh Python process per request (unacceptable latency from reloading model weights every call) are acceptable per `PLAN.md`. A small, persistent Python sidecar that loads both models once and serves them over internal HTTP solves this, and — per the architecture revision captured in `PLAN.md` — is scoped to ML serving only (`/embed`, `/rerank`); it has no CLI/subprocess responsibilities. It's the first buildable, independently-testable piece of the RAG pipeline: it has no dependency on the Rails app existing at all, so it can be built and proven correct via direct `curl` calls before any Ruby code touches it.

## What Changes

- Add a Python FastAPI application at `embedder/` with two endpoints:
  - `POST /embed` — takes a batch of texts, returns their embedding vectors (384-dim, via `sentence-transformers` `all-MiniLM-L6-v2`).
  - `POST /rerank` — takes a query and a list of candidate texts, returns relevance scores (via `cross-encoder/ms-marco-MiniLM-L-6-v2`).
- Both models load once at process startup (not per-request), so repeated calls hit warm models.
- Add `embedder/Dockerfile` building the service via `uv` (consistent with existing `mise`/`uv` tooling conventions in the user's other course repos).
- Add an `embedder` service to the existing `docker-compose.yml`, with a healthcheck that only reports healthy once both models have finished loading (not just once the HTTP process is up), so `web`/`worker` (added in later changes) can safely depend on it.
- Publish the service's port to the host (configurable via a new `EMBEDDER_PORT` env var, default `8001`), so it's directly `curl`-able from the host for local testing and peer review — acceptable for this project's dev/grading context, no auth added.
- Add `embedder/test.sh`, a `curl`+`jq` verification script exercising every scenario in `specs/embedding-service/spec.md` against a running instance, exiting non-zero on any failure.
- No `ansible-core`/`ansible-doc` in this container — that responsibility lives in the `worker` image, added in a separate change.

## Capabilities

### New Capabilities
- `embedding-service`: A containerized Python HTTP service that serves text-embedding and cross-encoder reranking scores from locally-loaded ML models, independent of and callable by any future Rails service.

### Modified Capabilities
(none — `postgres-database` is unaffected by this change)

## Impact

- **Affected files**: new `embedder/main.py`, `embedder/pyproject.toml` (or equivalent `uv` project files), `embedder/Dockerfile`, `embedder/test.sh`; `docker-compose.yml` gains an `embedder` service; `.env.example` gains `EMBEDDER_PORT`.
- **Dependencies**: `fastapi`, `uvicorn`, `sentence-transformers` (pulls in `torch` transitively) — no `ansible-core`.
- **Systems**: this is a standalone addition with no code depending on it yet (Rails app doesn't exist yet); later changes (ingestion's `EmbeddingClient`, retrieval's `RerankerClient`) will be the first real Ruby-side consumers. No breaking changes.
