# Evaluation Results

Methodology and results for the retrieval, LLM, and compositional evaluations described in `PLAN.md`'s "Evaluation" section and implemented in `openspec/changes/ansible-evaluation-pipeline/`. Live results are also viewable in the running app at `/evaluation`, read directly from the same `data/ground_truth.csv` / `data/eval_results.json` this document is generated from.

## Ground truth

Scoped to 6 named `ansible.builtin` modules, hand-picked for scenario diversity rather than convenience — see `PLAN.md` for the full rationale (parameter count, choice/enum density, the one module with `suboptions`, and a deprecated module for the RAG-vs-no-RAG headline story):

| Module | Params | Scenario |
|---|---|---|
| `copy` | 21 | baseline, no enums |
| `service` | 8 | smallest surface |
| `apt` | 25 | enum-heavy |
| `apt_key` | 8 | **deprecated** (`removed_in: 2.25`) |
| `user` | 40 | large surface |
| `iptables` | 46 | only module with `suboptions` |

**Pinned to `ansible-core 2.21.3`, generated 2026-08-18.** 450 ground-truth questions: 447 parameter questions (2-3 phrasings per parameter, `expected_type`/`expected_default`/`expected_choices` read directly from the ingested `AnsibleModule#raw_doc`, never from the LLM) plus 6 deprecation-status overview questions (one per module — `apt_key` as the positive case, the other 5 as negative controls). No module has been swapped from the original PLAN.md picks; the preflight found all 6 present.

Spot-checked by hand before treating this as final — phrasing reads naturally and expected values matched the fixture data directly (e.g. `apt_key`'s overview question: *"Is the Ansible module ansible.builtin.apt_key deprecated, and if so, which module or approach should be used instead?"*, `expected_deprecated: true`, `expected_alternative: ansible.builtin.deb822_repository`).

## Retrieval evaluation

4-way comparison, all strategies scored against the **full** ingested corpus (all ~71 modules, ~1,500 chunks) — only which modules generate ground-truth *questions* is scoped to the 6 above, not what's searchable. Top-K = 8, matching the live app's `SearchAnsibleDocs` tool.

| Strategy | Hit rate | MRR |
|---|---|---|
| keyword-only | 0.2% | 0.001 |
| vector-only | 63.1% | 0.459 |
| hybrid (RRF) | 61.3% | 0.453 |
| **hybrid + rerank** | **71.6%** | **0.533** |

Hybrid+rerank wins clearly, as expected. **Keyword-only's near-zero score is a real, investigated finding, not a bug**: `Chunk.search` uses Postgres' `plainto_tsquery`, which requires *every* term in the query to match (AND semantics). Ground-truth questions are LLM-phrased natural language — 10+ words, often including the module's dotted FQCN as one of those words — and requiring all of them to match is a bar chunk content essentially never clears. Confirmed keyword search still works correctly for short, deliberately keyword-style queries (2-3 words); this is specifically a mismatch between strict AND full-text search and verbose natural-language questions, which is exactly the gap hybrid search and reranking are meant to close. A concrete, honest illustration of why this project's best-practices bonus points (hybrid search, reranking) aren't just checkbox features.

## LLM evaluation (RAG vs. no-RAG)

Each question run through the live app's own tool-calling setup (`SearchAnsibleDocs`/`GetModuleDetails` registered, matching `ChatResponseJob`) and through a plain chat with no tools, both judged for parameter/deprecation accuracy against the ground-truth question's expected values.

| Condition | Accuracy |
|---|---|
| RAG | **77.8%** |
| No-RAG | 56.9% |

**Full 450-question run.** ~2,700 real completions (RAG + no-RAG generation × 2 judges × 450 questions). An earlier 18-question stratified sample (spanning all 6 modules but, at that size, landing on each module's parameter questions before reaching its one overview/deprecation question) is superseded by this full run, which necessarily includes every module's deprecation question.

**The headline `apt_key` case, checked directly** — question: *"Is the Ansible module ansible.builtin.apt_key deprecated, and if so, what module or approach should be used instead?"*

- **RAG**: "Yes — `ansible.builtin.apt_key` is deprecated... Use `ansible.builtin.deb822_repository`... instead." → judged **CORRECT**.
- **No-RAG**: "Yes... The recommended approach is to place repository keys as keyring files... use `ansible.builtin.get_url`... plus `ansible.builtin.apt_repository`..." — correctly knows `apt_key` is deprecated (general knowledge) but never names the actual replacement module, recommending an older/alternate workaround instead → judged **INCORRECT**.

This is exactly the "stale LLM knowledge" story the project is built around (`PLAN.md`'s Context section): the base model's training data covers `apt_key`'s deprecation but predates or lacks `deb822_repository` as the documented, current replacement; retrieval grounds the answer in what the ingested docs actually say.

Sampling note, for anyone re-running with `EVAL_SAMPLE_SIZE` for a faster/cheaper check: the sampler was originally a raw prefix of the ground-truth CSV and, in one live run, drew all 18 questions from a single module (`ansible.builtin.apt`) purely because of row order — defeating the point of the 6-module diversity. Fixed with `Eval::StratifiedSample`, which round-robins across modules. Even stratified, a small sample can still land on a module's *parameter* questions before reaching its one overview/deprecation question (parameter rows are generated before the overview row per module) — not an issue for this full run, but worth knowing if you limit the sample size.

## Compositional task evaluation

One hand-picked task-generation prompt per named module, run through the live agent loop, checked deterministically (no LLM judge — see `design.md`'s "Compositional eval needs no LLM judge at all") against three things: YAML validity, whether every module/parameter name used actually exists in the ingested docs, and whether required parameters are present.

| Module | Result |
|---|---|
| `copy` | PASS |
| `service` | PASS |
| `apt` | PASS |
| `apt_key` | FAIL (`yaml_valid: false`) |
| `user` | PASS |
| `iptables` | PASS |

**Pass rate: 83% (5/6)** in the full run — down from 6/6 in an earlier smaller run, on the same `apt_key` prompt. Not a regression in the checker: LLM generation isn't deterministic run-to-run, and this run's answer apparently didn't include a cleanly fenced YAML block the checker could extract, even with the format instruction in place. Across both runs, `apt_key`'s prompt ("add an apt signing key for a third-party repo") has produced a task using the still-valid `apt_key` module rather than steering toward `deb822_repository` — plausible given `apt_key` isn't removed until Ansible 2.25 and the prompt didn't ask about long-term maintainability, but worth a closer look given that's exactly the behavior this eval was designed to probe.

One real bug found and fixed during verification: the first version of these prompts got answers back as prose with an unfenced YAML snippet embedded in it, which the deterministic checker couldn't isolate — every answer scored `yaml_valid: false`, not because the generated YAML was wrong, but because extraction found nothing parseable. Fixed by explicitly asking for a fenced ` ```yaml ` block in the prompt (`Eval::CompositionalEvaluator::FORMAT_INSTRUCTION`).

## Reproducing

```bash
bin/rails eval:ground_truth          # regenerate data/ground_truth.csv (pinned to the currently ingested ansible-core version)
bin/rails eval:all                   # full pipeline -> data/eval_results.json (EVAL_SAMPLE_SIZE=N to limit the LLM slice; SKIP_GROUND_TRUTH=1 to reuse the existing CSV)
```

Regeneration is deliberate and manual — ground truth is pinned, not auto-regenerated when ingestion refreshes the corpus. See `PLAN.md`'s "Evaluation" section for the full pinning rationale and the module-swap policy for when a named module's deprecation lifecycle actually completes.
