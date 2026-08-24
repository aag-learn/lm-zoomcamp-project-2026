# LLM Zoomcamp Capstone: Ansible Module-Reference RAG Assistant (Rails)

> Captured from a planning conversation on 2026-08-04. Not yet implemented. Intended as input for a later OpenSpec-driven implementation pass (e.g. `openspec init` + turning the sections below into one or more change proposals) — nothing here assumes a particular OpenSpec version or directory layout, so adapt structure as needed when you set that up.

## Context

You've finished all 6 modules of the 2026-cohort LLM Zoomcamp and need a capstone project. You considered a stoicism-book chatbot but correctly flagged that general LLMs already interpret well-known public-domain texts without retrieval — a poor fit for the rubric's "Retrieval Flow" criterion, which penalizes projects where the LLM is just queried directly with no real knowledge-base benefit. We ruled out a CVE/NVD assistant (didn't genuinely interest you) and a generic "teach me Python/Go/Rust" tutor (same flaw as stoicism). We landed on **Ansible**, which you use heavily day-to-day: nobody reliably holds hundreds of modules' exact parameter names/types/defaults/choices in memory, so grounding answers in the real reference docs with citations is a genuine, defensible improvement over LLM free-recall.

Scope: **`ansible.builtin` collection only** (~70-90 modules), public docs/module-reference data (no private playbooks — keeps it simple and shareable).

**Key data-source discovery**: `ansible-doc -j <module>` (part of the `ansible-core` pip package) emits clean structured JSON per module — parameters with type/default/choices/required/version_added, deprecation notices, examples, return values — no scraping, no rate limits. Verified directly on this machine (e.g. `ansible.builtin.apt_key` is genuinely deprecated in favor of `deb822_repository` — a good concrete "stale LLM knowledge" example for the write-up).

**Language decision, reached through explicit elimination, not by default:**
- You have deep professional Ruby on Rails experience vs. Python at "just finished the course" level — implementation velocity favors Rails even without directly copy-pasteable homework snippets.
- We checked the course rubric text directly: the "Ingestion Pipeline" full-points tier says "Automated tool (Kestra/dlt/Airflow)" — those are named as *examples*, not a whitelist. The real distinction is scheduled/automatic vs. manually-run script. A recurring Rails job satisfies the same tier. (Practical caveat: this project is peer-reviewed by 3 fellow students trained on dlt/Kestra — make the automation obviously legible in the README so a reviewer doesn't dock a point out of unfamiliarity.)
- Chunking (`ansible-doc` JSON → structured records) is plain data transformation with no Python-specific dependency — Ruby's stdlib `JSON` handles it fine.
- The one place Python genuinely can't be avoided: local ML models (`sentence-transformers` bi-encoder for embeddings, `CrossEncoder` for reranking) don't have mature Ruby equivalents. Rather than call OpenAI's embeddings API (extra cost/latency/network dependency) or shell out to a fresh Python process per request (unacceptable latency — reloading model weights on every chat turn), the answer is a **small persistent Python sidecar service** that loads the models once and serves them over internal HTTP. This also solves model-consistency for free: ingestion-time document embeddings and live query embeddings hit the exact same warm model.

**Final architecture: Rails does everything (app, retrieval, agent loop, ingestion, evaluation) — including invoking the `ansible-doc` CLI directly from the `worker` process, since fetching raw module docs is squarely ingestion's own job; a narrow Python sidecar does only embedding and reranking.**

This means `worker` carries a Python + `ansible-core` install alongside its Ruby toolchain — the one deliberate mixed-runtime image in the system — while `web` and `embedder` each stay single-language. (Revised from an earlier version of this plan that put `ansible-doc` inside the embedder for language-purity reasons — "Python things live in the Python container." Traded that for stronger domain cohesion: ingestion owns its own data fetching end-to-end, and the embedder becomes truly single-responsibility, ML-serving only. The cost is that `worker`'s Dockerfile needs both toolchains, and the weekly `ansible-core` CI bump now targets `worker` instead of `embedder`.)

## Course rubric this project must satisfy (for reference)

10 categories × 2 pts (20 base) + bonus, from https://github.com/DataTalksClub/llm-zoomcamp/blob/main/project.md:
- Problem Description, Retrieval Flow (KB + LLM, not LLM-only), Retrieval Evaluation (multiple approaches), LLM Evaluation (multiple approaches), Interface (UI/web app/API for full points), Ingestion Pipeline (automated tool for full points), Monitoring (feedback AND 5+ chart dashboard for full points), Containerization (full docker-compose), Reproducibility.
- Best practices bonus (3 pts): hybrid search, document re-ranking, query rewriting.
- Cloud deployment bonus: 2 pts.
- Cannot reuse DataTalks.Club Zoomcamp FAQ documents as the data source (not a concern here).
- Peer review: evaluate 3 peer projects; separate GitHub repo required for submission.

## Repo setup

`llm-zoomcamp-project` (this directory) has no `.git` yet — nested inside the parent `datatalks.club` monorepo. Sibling repos (`llm-zoomcamp-homework`, `llm-zoomcamp-dlt-homework`) already use this same nested-independent-repo pattern.
1. `git init` inside `llm-zoomcamp-project`
2. `rails new . --database=postgresql --css=tailwind` (or your preferred CSS approach) inside the initialized repo
3. `.gitignore` — Rails default plus `.env`, `data/*.csv` if generated locally
4. `gh repo create` (private while iterating, flip public before submission — required for peer review)
5. Add `llm-zoomcamp-project/` to the parent monorepo's `.gitignore` so it stops showing as untracked there

## Directory layout

```
llm-zoomcamp-project/
├── app/
│   ├── controllers/  # chats_controller.rb etc. (generated by `bin/rails generate ruby_llm:chat_ui`) + dashboard_controller.rb
│   ├── models/
│   │   ├── ansible_module.rb, chunk.rb              # ingestion/retrieval domain
│   │   ├── chat.rb, message.rb, tool_call.rb        # RubyLLM-managed chat persistence — `acts_as_chat`/`acts_as_message`/`acts_as_tool_call`, kept as RubyLLM's own default names (not renamed to match the vocabulary below)
│   │   ├── retrieval_log.rb                         # one row per assistant Message: retrieval_strategy, retrieved_chunk_ids (jsonb), cost, response_time, top_module
│   │   └── feedback.rb                              # belongs_to :message — rating (+1/-1) per assistant reply
│   ├── services/
│   │   ├── embedding_client.rb          # HTTP client to sidecar /embed
│   │   ├── reranker_client.rb           # HTTP client to sidecar /rerank
│   │   ├── ansible_doc_client.rb        # shells out to `ansible-doc -j` (worker only)
│   │   ├── ingestion/chunker.rb         # raw module JSON -> 4 chunk types
│   │   ├── retrieval/keyword_search.rb  # pg_search / tsvector
│   │   ├── retrieval/vector_search.rb   # neighbor / pgvector cosine
│   │   ├── retrieval/hybrid_search.rb   # RRF merge
│   │   ├── retrieval/query_rewriter.rb  # LLM structured-output query expansion (bonus)
│   │   └── tools/search_ansible_docs.rb, tools/get_module_details.rb   # RubyLLM::Tool subclasses
│   ├── jobs/ingest_ansible_modules_job.rb   # Solid Queue recurring job
│   └── views/chats/, dashboard/
├── config/recurring.yml                 # Solid Queue schedule for ingestion job
├── config/initializers/ruby_llm.rb      # provider API keys, default model
├── db/migrate/                          # ansible_modules, chunks (vector + tsvector cols), chats/messages/tool_calls (RubyLLM), retrieval_logs, feedback
├── embedder/                            # Python sidecar — ML serving only (worker/ also has Python, for ansible-core)
│   ├── main.py                          # FastAPI: /embed, /rerank
│   ├── pyproject.toml
│   └── Dockerfile
├── lib/tasks/eval.rake                  # ground-truth gen, retrieval eval, LLM eval tasks
├── data/ground_truth.csv
├── docs/architecture.md, evaluation-results.md
├── docker-compose.yml
├── Dockerfile                           # Rails web image — pure Ruby
├── Dockerfile.worker                    # Rails worker image — same app/ codebase + Ruby, plus Python/ansible-core
├── Gemfile / Gemfile.lock
├── README.md, .env.example
```

## Python sidecar (`embedder/`)

Single FastAPI app, two endpoints, models loaded once at startup — ML serving only, no CLI/subprocess responsibilities (see "Ingestion" below for where `ansible-doc` lives):

```python
bi_encoder = SentenceTransformer("all-MiniLM-L6-v2")       # 384-dim, matches Chunk.embedding column
cross_encoder = CrossEncoder("cross-encoder/ms-marco-MiniLM-L-6-v2")

POST /embed    {texts: [...]}          -> {embeddings: [[...], ...]}
POST /rerank   {query, candidates}     -> {scores: [...]}
```

Runs via `uv` inside its own small Dockerfile (`fastapi`, `uvicorn`, `sentence-transformers`), consistent with the `uv`/`mise` tooling already used across your other course repos. No `ansible-core` here — that dependency lives in the `worker` image instead.

## Keeping ansible-core current (CI rebuild)

The Solid Queue job re-fetching on a schedule does not, by itself, get a newer Ansible release — `ansible-doc` is provided by whatever `ansible-core` version is pip-installed in the `worker` image at build time, and a long-running container doesn't pick up a newer PyPI release on its own. A separate, lightweight **scheduled GitHub Actions workflow** (independent of the in-app job schedule, e.g. weekly) handles this:
1. Bump `ansible-core` in `worker`'s dependency lockfile to the latest release (`uv lock --upgrade-package ansible-core`)
2. Rebuild the `worker` image only — `web` and `embedder` are untouched, since neither depends on `ansible-core`
3. Redeploy `worker` (self-hosted: pull + restart via docker-compose; cloud: push to registry + redeploy)

Once that lands, the *next* scheduled `IngestAnsibleModulesJob` run picks up the new version automatically — no cross-triggering/webhook plumbing needed between CI and Rails, which keeps the two schedules independent and simple. (A tighter design — CI directly triggers ingestion right after a successful rebuild, instead of waiting for the next independent timer — is a reasonable later refinement, not needed for the MVP.)

For the actual submission window, a real upstream `ansible-core` release probably won't land mid-build — treat this as an architecture point to demonstrate deliberately (pin an older version first, ingest, then bump the pin, rebuild, ingest again, and show the diff) rather than something to passively wait on.

## Ingestion (Ruby, `IngestAnsibleModulesJob`)

Solid Queue recurring job (Rails 8's DB-backed job backend — no Redis needed, fits cleanly with the existing Postgres service), scheduled via `config/recurring.yml` (e.g. weekly). Deliberately **no incremental update/diff logic** — every run is a full wipe-and-reload against whatever `ansible-core` version is currently installed in the `worker` image:
1. `AnsibleDocClient.fetch("ansible.builtin")` → shells out to `ansible-doc --list` then `ansible-doc -j <all names>` directly inside the `worker` container (one batched subprocess call; `ansible-core` is installed alongside Ruby there specifically for this), also capturing the installed `ansible-core` version via `ansible-doc --version`. No HTTP hop for this step — only step 3 (embedding) below talks to the `embedder` sidecar.
2. `Ingestion::Chunker.call(raw_json)` → 4 chunk types per module (`overview`, `parameter`, `examples`, `returns` — per-module chunking is too coarse for parameter-precision questions, per-sentence too fine). Stable IDs: `{fqcn}::overview`, `{fqcn}::param::{name}`, etc. Expect ~1,000-1,400 chunks total.
3. `EmbeddingClient.embed(chunk_texts)` (batched) → vectors for every chunk, unconditionally. Cheap: local model via the sidecar, CPU-seconds for ~1,400 short texts, no per-call dollar cost — so there's no meaningful waste being avoided by a fancier incremental/hash-based approach.
4. Inside a single DB transaction: `Chunk.delete_all`, then bulk-insert the freshly built chunk set, every row tagged with the same `ansible_core_version` for this run (trivial to get right, since every row in a run shares one version — no per-row diffing needed). The transaction is what makes "delete then reinsert" safe: if the job fails partway through (subprocess error, sidecar timeout, etc.), it rolls back and the *previous* successful data stays intact and queryable — the live app is never left mid-run with an empty or half-populated knowledge base. Same treatment for the raw `AnsibleModule` table.

This trades away any "only re-embed what changed" optimization, but that optimization wasn't saving anything meaningful here given free local embeddings — while the full wipe-and-reload sidesteps a whole class of bugs (orphaned chunks from removed modules/parameters, ambiguous version-tagging semantics on partial updates) for very little cost. Simpler to reason about, simpler to implement, and easy to verify: after any run, `Chunk.count` and `Chunk.distinct.pluck(:ansible_core_version)` should show exactly one version, matching the sidecar's `ansible-doc --version` output at run time.

Migration: `CREATE EXTENSION vector;`, `chunks` table with a `vector(384)` column (via the `pgvector`/`neighbor` gems), an `ansible_core_version` column, plus a `search_text` column with a `tsvector` generated column + GIN index for full-text search — keyword and vector search live in the *same table*, no separate in-memory index to maintain.

## Retrieval (Ruby, `app/services/retrieval/`)

- **Keyword**: `pg_search` scope (or raw `to_tsvector`/`plainto_tsquery`/`ts_rank`) over `Chunk.search_text`.
- **Vector**: `neighbor` gem's nearest-neighbor query (`Chunk.nearest_neighbors(:embedding, query_vector, distance: "cosine")`) after embedding the query via `EmbeddingClient`.
- **Hybrid**: Reciprocal Rank Fusion (k=60) merging the two ranked lists in plain Ruby — a hash of `chunk_id => Σ 1/(k+rank)`, sorted descending. Simpler and more defensible than score normalization across incompatible scales. Covers the **hybrid search bonus point**.
- **Query rewriting (bonus)**: OpenAI structured-output call (JSON schema response) expanding a vague question into Ansible-vocabulary search variants + an optional module hint; RRF-merge across variants.
- **Reranking (bonus)**: `RerankerClient` sends the RRF top ~20 candidates + original query to the sidecar's `/rerank`, keep top 5-8 for LLM context.

## Agent loop (Ruby, via RubyLLM)

**Revised 2026-08-10 — supersedes the `ruby-openai` plan below.** [RubyLLM](https://rubyllm.com/) (with its [Rails integration](https://rubyllm.com/rails/)) replaces the originally-planned `ruby-openai` gem and hand-rolled `AnsibleRagAgent` tool-calling loop. Reasons: it's multi-provider (not locked to OpenAI, which makes the LLM-eval rubric's "two prompts or two models through the same harness" close to a one-line swap), it has native `RubyLLM::Tool` classes that absorb the send-messages/execute-tool/repeat loop this plan was going to hand-roll, and its Rails generators (`ruby_llm:install`, `ruby_llm:chat_ui`) scaffold chat persistence and a Turbo Streams UI directly — de-risking the Interface rubric category, not just the agent logic.

- Two tools, as `RubyLLM::Tool` subclasses: `SearchAnsibleDocs` (`query:`, `module_filter:` — calls hybrid+rerank retrieval), `GetModuleDetails` (`fqcn:` — fetches the full parameter set for one exact module, from `AnsibleModule.raw_doc`).
- RubyLLM owns the request/response/tool-execution loop; no hand-rolled loop code. Token usage/cost comes from RubyLLM's own response metadata, written into `RetrievalLog` (see Persistence & UI) rather than a bespoke `Conversation` row.
- System/developer prompt encourages multi-step refinement ("search broadly first, then call `GetModuleDetails` once the exact module is identified").
- System/developer prompt explicitly permits and encourages **composing task/playbook YAML snippets**, not just answering definitional questions — e.g. "create a task to copy a file and set its permissions to 0666" should trigger broad search → module identification → `GetModuleDetails` for the complete parameter table → a generated snippet grounded in the real parameter names/types/defaults (not recalled from the model's own training). When the request is directionally ambiguous (e.g. "transfer a file to the host" could mean `copy`, `fetch`, or `template`), the agent should pick the most natural reading (push-to-remote → `copy`) or ask a brief clarifying question rather than silently guessing at a less likely module.
- **Real multi-turn conversations**: a `Chat` can have more than one exchange, and a follow-up question ("what about its `mode` parameter?") can lean on the prior turn's context — RubyLLM's `Chat`/`Message` history makes this natural rather than something to build separately. Ground-truth eval questions (see Evaluation) still run as fresh, single-exchange `Chat`s each — multi-turn is a live-app capability, not a new requirement on the eval harness.

## Persistence & UI

**Revised 2026-08-10** — chat persistence comes from RubyLLM's Rails integration (`bin/rails generate ruby_llm:install`), not a hand-rolled `Conversation` table. Kept as RubyLLM's own default model names (`Chat`, `Message`, `ToolCall`), not renamed — easier to match against the gem's own docs/community examples when something needs debugging.

- `Chat` / `Message` / `ToolCall` (RubyLLM-managed, via `acts_as_chat`/`acts_as_message`/`acts_as_tool_call`): the actual conversation transcript — one `Message` row per turn (user, assistant, tool call/result), one `Chat` per conversation thread. This is a different granularity than the original single-row-per-exchange `Conversation` design below — RubyLLM's schema wasn't going to be fought, so the app's own analytics needs are met by a second, narrower model instead (next item).
- `RetrievalLog`: one row per **assistant** `Message` — `retrieval_strategy`, `retrieved_chunk_ids` (jsonb), `cost`, `response_time`, `top_module`. Created alongside the assistant message once RubyLLM's tool-calling loop finishes, so the dashboard/eval queries below still get the "one row per Q&A exchange" shape they were designed around, without needing `Message` itself to carry app-specific columns.
- `Feedback`: `belongs_to :message` (not `:conversation`) — rating (+1/-1) on a specific assistant reply. Fits multi-turn naturally: each assistant message in a thread can be rated independently.
- Chat UI scaffolded by `bin/rails generate ruby_llm:chat_ui` (controllers/views/routes, Turbo Streams-driven), with `SearchAnsibleDocs`/`GetModuleDetails` tools wired in and retrieved-chunk citations rendered per assistant message, thumbs up/down writing to `Feedback`.

## Monitoring dashboard

`DashboardController` using `chartkick` + `groupdate` (`group_by_day`) directly against `RetrievalLog`/`Feedback` (not `Conversation` — see Persistence & UI revision) — no external account needed, which helps Reproducibility. 5 MVP charts + 2 stretch:
1. Query volume/day, 2. Latency/day, 3. Cost/day + running total, 4. Feedback ratio (thumbs up vs down)/day, 5. LLM-judge verdict distribution, 6. Top modules queried, 7. Low-confidence-retrieval rate/day.

## Evaluation (Ruby, `lib/tasks/eval.rake`)

Fully Ruby — eval calls the *exact same* service objects and RubyLLM tool-calling setup (`Retrieval::HybridSearch`, the `SearchAnsibleDocs`/`GetModuleDetails` tools) that the live app uses, so there's no risk of the evaluated code path diverging from production behavior. Each eval question runs as a fresh, single-exchange `Chat` (see Agent loop's multi-turn note).

**Revised 2026-08-18 — ground truth scoped to 6 named modules, not the full corpus.** The original plan generated ground truth from every `parameter` chunk across all ~70-90 ingested modules (~1,000+ questions). Reworked because LLM eval runs each question through the *real* agent loop — real completions, real tool calls, real judge calls — a fundamentally different cost/time profile than retrieval eval (local-embedding-only, effectively free). Thousands of questions makes LLM eval expensive and slow for no proportional benefit at capstone scope. Only *which modules generate ground-truth questions* is scoped down — the ingested/searchable corpus stays the full ~1,000-1,400 chunks across all modules, so retrieval still has to find the right chunk in a full-size haystack; the eval isn't made artificially easier.

The 6 modules, picked for scenario diversity, not convenience — verified directly against real `ansible-doc -j` output (params/choices/suboptions counted per module, not assumed):
- `copy` — small param surface (21), no choices/enums; baseline case, and the module in this plan's own compositional example below
- `service` — smallest param surface (8); common ensure-running/enabled pattern
- `apt` — enum-heavy (25 params, incl. `state: present/absent/latest/...`); pairs thematically with `apt_key`
- `apt_key` — **deprecated** (`alternative: ansible.builtin.deb822_repository`, confirmed live via `ansible-doc -j`); the anchor for the RAG-vs-no-RAG headline story
- `user` — large param surface (40 params); tests whether retrieval/generation degrades as a module gets big
- `iptables` — largest param surface (46) and, of all 71 `ansible.builtin` modules surveyed, the *only* one with `suboptions` (nested parameter structure) — the deliberately-hard structural case

**Ground truth is pinned to the `ansible_core_version` it's generated against, not auto-regenerated on every ingestion refresh.** The live app's corpus keeps auto-bumping via the weekly CI workflow (see "Keeping ansible-core current"), but a new release can silently break ground truth three ways: a parameter's default/choices change (old `expected_*` values go stale, so the LLM-eval judge starts marking newly-correct answers INCORRECT), a parameter gets renamed/removed (its `stable_id` no longer resolves to any chunk, so retrieval hit_rate/MRR reports an artificial miss instead of a real failure), or a module is removed from the collection outright. Tying ground-truth regeneration to the same automatic cadence as ingestion would reintroduce the cost problem this revision just trimmed (every CI bump triggering a full regen) and would make eval results non-reproducible run over run — a metric moving would leave no way to tell whether the *code* changed or the *data* changed. Instead: `data/ground_truth.csv` is checked into git, tagged with the `ansible_core_version` it was generated against, and only regenerated on a manual trigger, independent of how often the live app's corpus refreshes.

**Module-swap policy for `apt_key` (and any future removal)**: `apt_key`'s own `deprecated` payload states `removed_in: '2.25'` — the installed version at the time this plan was written is `2.21.2`, so real removal is a foreseeable event, not a hypothetical one. Because ground truth is pinned rather than auto-tracking, this can never happen silently — it only surfaces at the moment of a deliberate regeneration against a newer pinned version. That regeneration step includes checking each of the 6 modules' `deprecated` field against the new version and swapping in whichever `ansible.builtin` module is currently deprecated-but-not-yet-removed if `apt_key` (or any other picked module) has actually been removed by then, documenting the swap in `docs/evaluation-results.md`. Chosen over the alternative of treating the eventual removal itself as a deliberate demonstration point in the write-up: for a capstone, a demo that reliably works whenever a reviewer clones the repo matters more than a one-time illustrative coincidence of timing that only lands if review happens at exactly the right moment.

- **Ground truth**: for each `parameter` chunk belonging to one of the 6 modules above, an OpenAI structured-output call generates 2-3 questions, carrying the real `expected_type`/`expected_default`/`expected_choices` alongside — objectively checkable, not just a doc-ID match. ~148 parameters across the 6 modules → roughly 300-450 questions total, small enough to run the full agent loop over for LLM eval without a real cost/time concern. Parallelize with `concurrent-ruby`.
- **Overview ground truth — deprecation status only**: a second, narrower ground-truth slice from the same 6 modules' `overview` chunks, scoped specifically to deprecation (`expected_deprecated: true/false`, `expected_alternative` when applicable) rather than generic "what does this module do" questions — the latter aren't objectively checkable and would just duplicate what the generic-relevance LLM-eval judge below already covers. `apt_key` is the positive case; the other 5 (non-deprecated) modules act as negative controls, so this also catches false-positive deprecation claims. **Currently blocked on a chunker gap found while designing this eval**: `Ingestion::Chunker#overview_chunk` only pulls `short_description`/`description`/`notes`/`seealso` — the `deprecated` field is never written into any chunk's content (confirmed by reading `app/services/ingestion/chunker.rb` and cross-checking real `ansible-doc -j ansible.builtin.apt_key` output, which does carry `deprecated.alternative`/`deprecated.why`). Without this, the `apt_key` headline story can't succeed regardless of retrieval quality — needs a small chunker fix (include deprecation info in the overview chunk) as a fast-follow, tracked here rather than fixed silently.
- **Return-value ground truth: explicitly out of scope.** Considered and dropped, not just deferred by omission — output-schema questions ("what type does this module return") are real but secondary to the project's core value prop (playbook authors care far more about input parameters than return shapes), and this revision is already trimming ground-truth volume rather than adding a fifth source. Revisit only if time remains after parameter/overview/compositional evals are solid.
- **Retrieval eval**: `hit_rate`/`mrr` (rank position of the expected `chunk_id` in each strategy's results) across keyword-only, vector-only, hybrid, and hybrid+rerank (4 strategies, comfortably clears "multiple approaches evaluated") — run over the full ground-truth set (parameter + deprecation-overview questions), searched against the *full* ingested corpus (all ~70-90 modules), not just the 6.
- **LLM eval**: two OpenAI structured-output judges — generic relevance, and a domain-specific `param_accuracy` verdict (CORRECT/INCORRECT/NOT_STATED) checking whether the generated answer's stated default/type/choices match ground truth. Primary comparison: **RAG vs. no-RAG** accuracy delta (use the `apt_key` deprecation as a concrete headline example, once the chunker gap above is fixed). Secondary: two prompts or two models through the same harness.
- **Compositional task eval** (separate from the parameter-lookup eval above, **now drawn from the same 6-module list** rather than an independently hand-picked set — one named, explainable module set anchors the whole evaluation write-up, instead of two disconnected samples): the parameter-chunk ground truth only tests factual recall ("what does X default to"), not the arguably more realistic day-to-day use case of "write me a working task that does X." One hand-picked task-generation prompt per module (6 total — tightened from the originally-planned 10-20, alongside the rest of this revision):
  - `copy`: "create a task to copy a file to the host and set its permissions to 0666" — the `mode: 0666` vs `mode: '0666'` quoting gotcha (a real, documented Ansible footgun around unquoted octal-looking values in YAML) is the deliberate test case here
  - `service`: "write a task to restart a service only when a config file changes"
  - `apt`: "write a task to install a package only if not already present"
  - `apt_key`: "add an apt signing key for a third-party repo" — checks whether the agent steers toward `deb822_repository` instead of a deprecated `apt_key` task, once retrieval can see the deprecation
  - `user`: "create a task to add a system user with a specific shell and home directory, without a login password"
  - `iptables`: "write a task to open TCP port 443 on the INPUT chain" — exercises the suboption-shaped parameters

  No single correct answer, so this is judged qualitatively rather than exact-match: an OpenAI structured-output judge checks (a) the YAML is syntactically valid, (b) module/parameter names used actually exist in the ingested docs (catches hallucinated parameters), (c) required parameters are present.

**Added 2026-08-18 — ground truth and eval results get their own in-app page, not just files in the repo.** Reviewers are already interacting with the running app for the Interface rubric category; surfacing eval numbers where they're already looking beats requiring a trip into the repo to read `docs/evaluation-results.md`. Kept deliberately read-only and separate from the earlier discussion of live-triggered regeneration — this only *displays* already-generated, checked-in artifacts:

- `lib/tasks/eval.rake` writes `data/ground_truth.csv` (as already planned) plus a compact `data/eval_results.json` (hit_rate/MRR per retrieval strategy, RAG-vs-no-RAG accuracy deltas, compositional-eval pass rates, the `ansible_core_version` and generation timestamp the run was pinned to).
- A new page (its own nav entry, e.g. `EvaluationsController#show`) reads both files directly off disk at request time and renders them — no new `ActiveRecord` model or migration. Considered and rejected: persisting eval runs to the DB would just be a persistence layer for something that's already a file, and results only change on a deliberate, manual regeneration (see the pinning decision above) — not the kind of continuously-accumulating data a table earns its keep for. Matches this project's standing bias against introducing abstractions the data doesn't need.
- Kept as its own page rather than folded into the Monitoring dashboard above, despite both being "numbers in the app": Monitoring is continuous live telemetry off `RetrievalLog`/`Feedback` (query volume, cost, feedback ratio — accumulates with every real chat turn); this page is a periodic offline benchmark against a pinned snapshot. Distinct cadence, distinct data source, distinct rubric category (Monitoring vs. Retrieval/LLM Evaluation) — keeping them visually separate makes it easier for a reviewer scanning the app to see both boxes checked independently, rather than untangling one merged screen.
- The page carries a small static notice explaining how to regenerate, e.g.: *"Results pinned to `ansible-core 2.21.2` as of 2026-08-20; regenerate via `bin/rails eval:generate_ground_truth && bin/rails eval:run` — see PLAN.md for methodology."* — regeneration itself stays CLI-only (per the manual-trigger pinning decision); the notice exists purely so a reviewer understands why the numbers aren't live and how to reproduce them, which also feeds the Reproducibility rubric category.

## Containerization

`docker-compose.yml`:
```yaml
services:
  postgres:   # pgvector-enabled image
  embedder:   # Python sidecar, ML-serving only (build: ./embedder), always-on
  web:        # Rails app (build: .), pure Ruby, depends_on postgres + embedder healthchecks
  worker:     # `bin/jobs` — Solid Queue process running the recurring ingestion job
              # (build: ., dockerfile: Dockerfile.worker) — Ruby + Python/ansible-core, the one mixed-runtime image
```
Three Dockerfiles (`Dockerfile` for the Ruby-only `web` image, `Dockerfile.worker` for the Ruby+`ansible-core` worker image — same `app/` codebase and build context as `web`, different image — and `embedder/Dockerfile` for the Python-only sidecar) — `web` and `worker` deliberately don't share a single built image, since `worker` is the one place that mixes runtimes so ingestion can own its own data fetching without pulling Python into the user-facing `web` image. Whoever clones the repo still only needs Docker, not Ruby *and* Python locally, so Reproducibility stays clean.

## Build order (1-2 weeks)

**Week 1** — touch every base rubric category by end of week so week 2 is depth/bonus, not scrambling:
- Day 0: repo init, `rails new`, `embedder/` scaffold (FastAPI + models loading), `Dockerfile.worker` scaffold (Ruby + `ansible-core`, smoke-tested with a direct `ansible-doc -j` call), `docker-compose.yml` skeleton (postgres + embedder + worker booting)
- Day 1: migrations (`ansible_modules`, `chunks` with vector+tsvector), `AnsibleDocClient`, `IngestAnsibleModulesJob` landing raw JSON
- Day 2: `Ingestion::Chunker` (4 types) + `EmbeddingClient` populating `chunks.embedding`
- Day 3: keyword/vector/hybrid retrieval services → baseline Retrieval Flow done
- Day 4: RubyLLM tool-calling setup (`SearchAnsibleDocs`/`GetModuleDetails`), working answers from a console/rake smoke test → MVP milestone
- Day 5: `ruby_llm:chat_ui`-generated chat UI + `RetrievalLog`/`Feedback` logging → Interface done
- Day 6-7: ground-truth generation rake task

**Week 2**:
- Day 8: retrieval eval rake task, 4-way comparison → Retrieval Evaluation done
- Day 9: `RerankerClient` + `QueryRewriter` → all 3 best-practice bonus points achievable
- Day 10: LLM eval rake task (RAG vs no-RAG + param-accuracy judge) → LLM Evaluation done
- Day 11: `DashboardController` + views, 5-7 charts → Monitoring done
- Day 12: finalize `docker-compose.yml`/Dockerfiles, clean-checkout smoke test → Containerization done
- Day 13: README (setup, "how to get the data" = run the ingestion job once, how to reproduce eval — explicitly explain the recurring-job automation for peer reviewers), `.env.example`, `docs/architecture.md`, push to GitHub → Reproducibility + Problem Description done
- Day 14 (buffer): cloud deploy — Fly.io/Render for `web`+`worker`, a pgvector-capable managed Postgres (Fly Postgres or Neon), and the `embedder` sidecar as its own small always-on service → cloud deployment bonus

## Verification

- Ingestion: run the job (`bin/rails runner 'IngestAnsibleModulesJob.perform_now'` or via the queue), then `Chunk.count` — expect ~1,000-1,400.
- Sidecar: `curl` `/embed` and `/rerank` directly against the running `embedder` container to confirm each independently before wiring Rails to them.
- Ingestion fetch: run `docker compose run worker ansible-doc -j ansible.builtin.copy` (or equivalent) directly to confirm `ansible-core` is correctly installed and callable inside the `worker` image before wiring up `AnsibleDocClient`.
- Retrieval: run the retrieval-eval rake task, confirm hit-rate/MRR print and hybrid ≥ either single strategy.
- Agent: manually ask the running app a real question (e.g. "what does the `mode` parameter of the copy module default to") and confirm the answer cites the correct module/parameter.
- LLM eval: run the LLM-eval rake task, confirm the RAG-vs-no-RAG table shows a measurable accuracy gap, with `apt_key` deprecation as a spot-check case.
- Full stack: `docker compose up`, open the app, send a message, click thumbs up/down, open the dashboard and confirm the new data point appears.
- Version bump: run the CI rebuild workflow (or its steps locally) against a downgraded `ansible-core` pin, ingest, then bump to latest, rebuild, ingest again — confirm `Chunk.distinct.pluck(:ansible_core_version)` shows only the new version afterward (proves the wipe-and-reload is complete, not partial). Good source for a before/after screenshot in the README too.
- Atomicity: kill the ingestion job mid-run (e.g. `kill -9` the process) and confirm the app still serves the previous chunk set afterward, not an empty one (transaction-rollback check).
- Before submission: fresh clone into a scratch dir, follow only the README, confirm `docker compose up` + one documented ingestion-trigger step works end-to-end (Reproducibility check).

## Remaining work (as of 2026-08-19)

Retrieval Flow, Retrieval Evaluation, LLM Evaluation, Interface, Ingestion Pipeline, Monitoring, and Containerization are done (see `openspec/changes/archive/`). This section lists what's left, split by whether it actually affects rubric scoring — so effort goes to points first, polish second.

**Rubric gaps — base points (2 pts each):**
- **Problem Description**: the README has no problem statement at all — just setup steps. Needs a short section explaining what the app is and why it exists (the "nobody memorizes 90 modules' exact parameter defaults" framing from this doc's Context section).
- **Reproducibility**: the README is stale, not just thin — it still describes the `prepare_db` service, removed two changes ago, and never mentions Grafana (port, login, or that `/monitoring` and `/evaluation` pages exist). `docs/architecture.md`, planned for Day 13, was never written. The Verification section's "fresh clone, README-only" smoke test hasn't been re-run since the startup-dependencies rework or the monitoring dashboard landed.

**Rubric gaps — bonus points:**
- **Query rewriting** (1 of the 3 best-practice bonus points; hybrid search and reranking are both done): most valuable as conversational query condensation, not generic expansion — this app already has multi-turn chat, but each `SearchAnsibleDocs` call is a stateless search with no explicit context-carrying step. A follow-up like "what about for `template`?" has nothing on its own for keyword/vector search to match.
- **Cloud deployment** (2 pts): not attempted. Fly.io/Render for `web`/`worker`, managed pgvector-capable Postgres, `embedder` as its own always-on service — see Day 14 above.

**Named in this plan but not yet built, not directly point-scoring on its own:**
- The weekly GitHub Actions `ansible-core` freshness workflow ("Keeping ansible-core current" section above) — `.github/workflows/` doesn't exist yet. Ingestion Pipeline already scores via the recurring in-app job regardless; this is about the freshness story being real rather than assumed, and it's what the Verification section's "version bump" demo depends on.

**Nice-to-haves — not separately rubric-scored:**
- Paginate the chat page.
- ~~Local dev environment cleanup~~ — done via `openspec/changes/local-dev-environment/` (not yet archived): `web`/`worker`/`embedder` now run as local processes (`bin/dev` + `mise run db:prepare`/`ingest` + `uv run uvicorn`), `ansible-core` via `mise`, `dotenv-rails` for `.env` loading, Postgres/Grafana still via `docker compose`. Building it live surfaced and fixed three real gaps development never had before (Solid Queue's `queue` database/adapter, Action Cable's `async`-only-works-single-process limitation once `worker` became a separate process, Grafana's datasource being hardcoded to `production`).
- `hide-tool-orchestration-messages` (proposed earlier, still 0/10 tasks) — raw tool-call/result bubbles currently leak into the chat UI instead of being hidden/summarized.
- **Monitoring likely undercounts real usage**: `RetrievalLog` (what every Grafana/`/monitoring` panel reads) is only created when the LLM specifically calls the `SearchAnsibleDocs` tool and gets hits (`app/jobs/chat_response_job.rb`) — there is no system prompt anywhere in the app steering the agent toward that tool first, despite this doc's Agent loop section describing one ("search broadly first, then call `GetModuleDetails`"). Confirmed directly (2026-08-23): even this doc's own canonical example question ("what does the mode parameter of the copy module default to") produces a `GetModuleDetails`-only tool call, no `SearchAnsibleDocs` call, hence no `RetrievalLog` row. Needs investigation: add the missing system prompt, decouple monitoring logging from that one specific tool call, or both. Noted for later, not investigated yet.
