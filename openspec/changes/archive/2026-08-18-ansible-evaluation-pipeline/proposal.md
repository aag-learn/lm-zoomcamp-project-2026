## Why

The app ingests, retrieves, and answers questions, but has no evaluation harness at all — the rubric's Retrieval Evaluation and LLM Evaluation categories (each requiring "multiple approaches") are currently unaddressed, and there's no way to substantiate the RAG-vs-no-RAG value proposition this project is built around. Separately, while designing that eval, we found that `Ingestion::Chunker#overview_chunk` never includes a module's `deprecated` field (confirmed against real `ansible-doc -j ansible.builtin.apt_key` output, which does carry `deprecated.alternative`/`deprecated.why`) — so the eval's planned headline example (RAG correctly surfacing `apt_key`'s deprecation, a bare LLM not) can't succeed regardless of retrieval quality. Both are bundled into one change because the eval cannot be meaningfully verified without the chunker fix landing first.

## What Changes

- Fix `Ingestion::Chunker#overview_chunk` to include a module's deprecation status (alternative module, reason) in its content when `deprecated` is present, so deprecation becomes retrievable like any other documented fact.
- Add a ground-truth generation rake task scoped to 6 hand-picked `ansible.builtin` modules (`copy`, `service`, `apt`, `apt_key`, `user`, `iptables` — chosen for parameter-count/enum-density/suboptions/deprecation diversity, verified against real `ansible-doc -j` output), producing two slices: per-parameter Q&A (`expected_type`/`expected_default`/`expected_choices`) and deprecation-focused overview Q&A (`expected_deprecated`/`expected_alternative`), written to a checked-in `data/ground_truth.csv` pinned to the `ansible_core_version` it was generated against. Return-value ground truth is explicitly excluded.
- Add a module-swap preflight to that same rake task: before generating, check each of the 6 modules' `deprecated` field against the currently-ingested `ansible-core` version and warn if one has actually been removed from the collection, so a stale module pick surfaces as a deliberate decision rather than a silently-broken eval.
- Add a retrieval eval rake task computing `hit_rate`/`mrr` across 4 strategies (keyword-only, vector-only, hybrid, hybrid+rerank) over the full ground-truth set, searched against the full ingested corpus (not just the 6 modules).
- Add an LLM eval rake task with two OpenAI structured-output judges (generic relevance, and a domain-specific `param_accuracy` verdict), computing a primary RAG-vs-no-RAG accuracy delta and a secondary two-prompt-or-two-model comparison, reusing the live app's own `Retrieval::HybridSearch` and `SearchAnsibleDocs`/`GetModuleDetails` tool-calling setup rather than a separate eval-only code path.
- Add a compositional task eval (one hand-picked task-generation prompt per module, same 6-module list) judged for YAML validity, real (non-hallucinated) module/parameter names, and required-parameter presence.
- Add a read-only, file-backed "Evaluation" page in the app (its own nav entry, distinct from the not-yet-built Monitoring dashboard) that reads `data/ground_truth.csv` and a new `data/eval_results.json` directly off disk and renders them, with a static notice on how to regenerate. No new `ActiveRecord` model or migration.

## Capabilities

### New Capabilities
- `ansible-evaluation`: ground-truth generation (pinned, 6-module-scoped, with a module-swap preflight), retrieval eval, LLM eval, compositional task eval, and a read-only in-app page displaying the results.

### Modified Capabilities
- `ansible-ingestion`: the "Module documentation is split into retrievable chunks" requirement's overview-chunk behavior changes — a deprecated module's overview chunk must now include its deprecation status, not just summary description.

## Impact

- `rails_app/app/services/ingestion/chunker.rb` — `overview_chunk` gains deprecation content.
- `rails_app/lib/tasks/eval.rake` (new) — ground-truth generation, retrieval eval, LLM eval, compositional eval tasks.
- `rails_app/data/ground_truth.csv`, `rails_app/data/eval_results.json` (new, checked-in generated artifacts).
- `rails_app/app/controllers/evaluations_controller.rb`, associated view(s), route, nav entry (new).
- Reuses without modifying: `Retrieval::HybridSearch`/`KeywordSearch`/`VectorSearch`, `RerankerClient`, `SearchAnsibleDocs`/`GetModuleDetails` tools, `Chunk`/`AnsibleModule` models.
- No changes to `hide-tool-orchestration-messages` (separate, still-unimplemented change) or to the Monitoring dashboard (not yet built).
