## Why

The live chat and the LLM-eval harness both register `SearchAnsibleDocs`/`GetModuleDetails` as tools with no `.with_instructions(...)` system prompt anywhere in the codebase, despite `PLAN.md`'s "Agent loop" section describing one. Since `gpt-5-mini` already knows common Ansible module fqcns from training, it routinely skips `SearchAnsibleDocs` and answers via `GetModuleDetails` alone (confirmed live, including with `PLAN.md`'s own canonical example question) — defeating the actual point of RAG here, since the ingested corpus is pinned to a specific `ansible_core_version` that may differ from what the model recalls. A second, compounding effect: `RetrievalLog` (`app/jobs/chat_response_job.rb:18`) is only created when a search actually happened and found something, and every Grafana Monitoring panel reads exclusively from `retrieval_logs` — so any chat turn that doesn't trigger a search isn't just mis-attributed, it's invisible to Monitoring entirely (no query counted, no cost, no latency). `Eval::LlmEvaluator#ask_with_tools` has the identical gap, so the eval's headline RAG-vs-no-RAG accuracy comparison may not be exercising real retrieval either.

## What Changes

- `ChatResponseJob#perform` gets a `chat.with_instructions(...)` call before `chat.ask(content)`, explaining that the ingested corpus is pinned to a specific `ansible_core_version` and the model should verify parameter facts via search rather than rely on training memory alone.
- `ChatResponseJob#perform` and `Eval::LlmEvaluator#ask_with_tools` both force `choice: :search_ansible_docs` on `with_tools`, guaranteeing `SearchAnsibleDocs` is invoked on the first tool-call round of every real chat turn and every RAG-condition eval question. `SearchAnsibleDocs#execute` is unchanged — it keeps returning whatever hybrid+rerank finds, with no relevance/confidence filtering.
- `ChatResponseJob#build_retrieval_log` fires unconditionally (drops the `if search_tool.retrieved_chunks.any?` guard) — one `RetrievalLog` row per real assistant exchange, always, logging whatever was actually retrieved (including empty/low-relevance results, honestly).
- `grafana/dashboards/chat-monitoring.json`'s "low confidence rate" panel is removed — its hardcoded `rerank_score < 0.3` threshold predates any real calibration and is meaningless against the reranker's actual raw-logit score range; this change deliberately does not replace it with a calibrated alternative.
- No change to `_citations.html.erb`, `_assistant.html.erb`, or the tool-orchestration message rendering — that's `hide-tool-orchestration-messages`' scope, updated separately this session to handle the citation-display consequence of unconditional `RetrievalLog` logging.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `ansible-retrieval`: "Assistant replies can be grounded in retrieved documentation" changes from "the assistant can search" to "search is structurally guaranteed on the first round of every turn"; "Every retrieval-grounded reply is logged" changes from conditional-on-retrieval-happening to unconditional per assistant reply.
- `monitoring`: "Grafana dashboard reflects live chat traffic" changes from "reflects traffic where retrieval fired" to "reflects all chat traffic" now that logging is unconditional.
- `ansible-evaluation`: "LLM evaluation compares RAG-grounded and non-grounded answers" changes so the RAG condition structurally exercises retrieval rather than allowing the model to bypass it.

## Impact

- `app/jobs/chat_response_job.rb` — `with_instructions`, forced `tool_choice`, unconditional `build_retrieval_log`.
- `app/services/eval/llm_evaluator.rb` — forced `tool_choice` on `ask_with_tools`.
- `grafana/dashboards/chat-monitoring.json` — "low confidence rate" panel removed.
- `openspec/specs/ansible-retrieval/spec.md`, `openspec/specs/monitoring/spec.md`, `openspec/specs/ansible-evaluation/spec.md` — requirement wording updated per Capabilities above.
- No changes to `SearchAnsibleDocs`, `GetModuleDetails`, `Retrieval::*`, `RerankerClient`, or any citation-rendering view — those are unaffected or owned by the sibling `hide-tool-orchestration-messages` change.
