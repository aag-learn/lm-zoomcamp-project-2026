## Why

The chat works end-to-end (`chat-interface-scaffolding`, styled in `enable-tailwindcss`) but the assistant currently answers purely from its own trained knowledge — `ChatResponseJob` calls `chat.ask(content)` with zero tools registered. The whole point of this project (per `PLAN.md`'s original framing) is grounding Ansible questions in real, current reference docs instead of LLM free-recall. Ingestion already populated 1,538 real, embedded chunks with nothing reading them yet. This change closes that gap: wires real hybrid+rerank retrieval into the chat via tool-calling, logs what was retrieved, and shows citations.

## What Changes

- Add `Retrieval::KeywordSearch`, `Retrieval::VectorSearch`, `Retrieval::HybridSearch` services — the first two wrap already-existing primitives (`Chunk.search`, `Chunk`'s `has_neighbors :embedding`), the third does Reciprocal Rank Fusion (k=60) over their results. Kept as independently-callable services, not collapsed into one method, so a later Retrieval Evaluation change can compare all 4 strategies (keyword-only, vector-only, hybrid, hybrid+rerank) directly.
- Add `RerankerClient` — a new Faraday-based HTTP client to the `embedder` sidecar's existing `POST /rerank`, mirroring `EmbeddingClient`'s established pattern (retry middleware, webmock tests).
- Add two `RubyLLM::Tool` subclasses: `SearchAnsibleDocs` (`query:`, `module_filter:` — always runs the full hybrid+rerank pipeline, no strategy selection exposed) and `GetModuleDetails` (`fqcn:` — reads `AnsibleModule.raw_doc`).
- Register both tools on the chat in `ChatResponseJob` via `chat.with_tools(search_tool, GetModuleDetails)` — a pre-built `SearchAnsibleDocs` *instance* (not the class) so its accumulated retrieval results can be read back afterward for `RetrievalLog`; confirmed against the installed `ruby_llm` 1.16.0 gem source that `with_tool`/`with_tools` accept either a class or an instance.
- Add `RetrievalLog` model + migration — one row per assistant `Message`: `retrieval_strategy`, `retrieved_chunks` (jsonb array of `{stable_id, rrf_score, rerank_score}` objects — `stable_id` not numeric `Chunk.id`, both the hybrid-merge score and the reranker's final relevance score kept per chunk; see design.md), `ansible_core_version`, `cost`, `response_time`, `input_tokens`, `output_tokens`, `top_module`.
- Render citations under each assistant message, reading from its `RetrievalLog`, resolving `stable_id`s back to `Chunk`s at render time (gracefully omitting any that no longer exist).

Explicitly **not** in this change (deferred to later, separate changes): the Retrieval Evaluation rake task (ground-truth generation, 4-strategy hit-rate/MRR comparison), and query rewriting.

**Corrected during design, before implementation started**: `PLAN.md`'s original phrasing had `retrieved_chunk_ids` as `jsonb` holding numeric chunk identifiers. Caught during design review: `ansible-ingestion-pipeline`'s `IngestAnsibleModulesJob` does a full wipe-and-reload every week — every chunk gets a brand-new numeric `id` on every run, so numeric IDs stored today would silently point at nothing (or, worse, be misinterpreted) after the next scheduled ingestion. Fixed by storing `Chunk.stable_id` strings instead (the identifier already verified, back in `ansible-ingestion-pipeline`, to survive re-ingestion), plus denormalizing `ansible_core_version` onto `RetrievalLog` so provenance survives even if every referenced `stable_id` is later removed from a newer Ansible release. Considered and explicitly rejected switching ingestion itself to archive-instead-of-delete chunks (would fully solve it, including for removed parameters) — rejected because it reopens `ansible-ingestion-pipeline`'s already-shipped, already-synced spec text and job logic (a partial unique index, `where(archived_at: nil)` on every retrieval query, real upsert logic replacing the deliberately-simple wipe-and-reload) for a narrow edge case (a parameter fully removed from a later release) that `stable_id`-based storage already degrades gracefully on.

Also decided to keep each retrieved chunk's **both** scores alongside its `stable_id` — the RRF hybrid-merge score and the reranker's final score, not just one (renamed the field to `retrieved_chunks`, holding `[{stable_id:, rrf_score:, rerank_score:}, ...]`) — keeping both preserves visibility into whether reranking actually changes the outcome versus the hybrid ranking alone, useful for a later Retrieval Evaluation change without needing to re-run retrieval against historical queries. This richer per-chunk shape a flat list of strings can't hold is also what settled the storage-type question: `jsonb`, not a native Postgres array (a flat array was briefly considered and rejected once the scores made the richer object shape necessary). `Retrieval::HybridSearch` itself had to change shape to make this possible — it now returns small `(chunk, rrf_score)` pairs rather than bare `Chunk` records, so the RRF score survives past the merge step instead of being discarded once it's done ordering the candidates.

## Capabilities

### New Capabilities
- `ansible-retrieval`: hybrid+rerank retrieval over ingested Ansible module chunks, exposed to the chat agent via tool-calling, logged per assistant reply, and cited in the UI.

### Modified Capabilities
(none — `chat-interface`'s existing 6 requirements are unaffected; none of them constrain how an assistant reply is generated internally, so adding tool-based grounding doesn't change any of their wording)

## Impact

- **New**: `app/services/retrieval/keyword_search.rb`, `vector_search.rb`, `hybrid_search.rb`, `app/services/reranker_client.rb`, `app/tools/search_ansible_docs.rb`, `app/tools/get_module_details.rb`, `app/models/retrieval_log.rb`, `db/migrate/*_create_retrieval_logs.rb`.
- **Modified**: `app/jobs/chat_response_job.rb` (tool registration, `RetrievalLog` creation), chat message views (citation rendering).
- **No changes to**: ingestion pipeline, `Chunk`/`AnsibleModule` schema, the `embedder` sidecar (already implements `/rerank`), `chat-interface`'s spec.
