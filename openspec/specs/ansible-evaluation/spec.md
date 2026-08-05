## Purpose

Provide a reproducible way to measure retrieval quality and answer quality against a fixed, checkable ground-truth set, and to surface those results inside the running application so they're visible without reading repository files.

## Requirements

### Requirement: Ground truth is scoped to a fixed set of named modules
The system SHALL generate ground-truth question/answer pairs only from a fixed, named set of modules, not from every ingested module, so that ground-truth volume stays bounded regardless of total corpus size.

#### Scenario: Ground truth covers only the named modules
- **WHEN** ground truth is generated
- **THEN** every generated question is derived from a parameter or overview chunk belonging to one of the named modules, and no question is derived from a module outside that set

### Requirement: Ground truth includes objectively checkable expected values
The system SHALL generate, for each parameter-derived question, an expected type, expected default, and expected choices (when applicable) alongside the question text, and SHALL generate, for each deprecation-derived question, an expected deprecated status and expected alternative module (when applicable) — so answers can be checked against a concrete expected value rather than judged as free text alone.

#### Scenario: A parameter question carries checkable expected values
- **WHEN** a ground-truth question is generated from a parameter chunk
- **THEN** the question is stored together with that parameter's actual type, default, and choices as documented at generation time

#### Scenario: A deprecation question carries a checkable expected status
- **WHEN** a ground-truth question is generated from a module's overview chunk
- **THEN** the question is stored together with that module's actual deprecated status, and its replacement module when one is documented

#### Scenario: Non-deprecated modules produce negative-control questions
- **WHEN** ground truth is generated for a module that is not deprecated
- **THEN** at least one generated overview question expects a "not deprecated" answer for that module

### Requirement: Return-value documentation is excluded from ground truth
The system SHALL NOT generate ground-truth questions from return-value chunks.

#### Scenario: No question references a return value
- **WHEN** ground truth is generated
- **THEN** no generated question is derived from a return-value chunk

### Requirement: Ground truth is pinned to the ingested ansible-core version and regenerated only on request
The system SHALL tag a generated ground-truth set with the `ansible-core` version active at generation time, SHALL persist it so it survives independently of any later ingestion run, and SHALL NOT regenerate it automatically when ingestion refreshes the corpus.

#### Scenario: Ground truth records its generation version
- **WHEN** ground truth is generated
- **THEN** the stored ground-truth set records the `ansible-core` version that was active at generation time

#### Scenario: An ingestion run does not change existing ground truth
- **WHEN** an ingestion run completes and replaces the corpus with a newer `ansible-core` version
- **THEN** the previously generated ground-truth set is left unchanged, still tagged with the version it was generated against

### Requirement: Ground-truth generation warns when a named module is no longer available
The system SHALL check, before generating ground truth, whether each named module is still present (and, if deprecated, not yet removed) in the currently ingested corpus, and SHALL warn rather than silently produce an incomplete or broken ground-truth set when one is not.

#### Scenario: A named module has been removed from the corpus
- **WHEN** ground-truth generation runs and a named module is absent from the currently ingested modules
- **THEN** generation surfaces a warning identifying that module before producing output, rather than silently omitting it

### Requirement: Retrieval evaluation compares multiple retrieval strategies against the full corpus
The system SHALL evaluate retrieval quality (hit rate and mean reciprocal rank of the expected chunk) for each ground-truth question, independently for keyword-only, vector-only, hybrid, and hybrid-with-reranking retrieval, searching the entire ingested corpus rather than only the named modules' chunks.

#### Scenario: Each strategy is scored independently
- **WHEN** retrieval evaluation runs
- **THEN** a hit-rate and mean-reciprocal-rank score is produced for each of the four retrieval strategies, computed against the full ingested corpus

### Requirement: LLM evaluation compares RAG-grounded and non-grounded answers
The system SHALL, for each ground-truth question, generate an answer using retrieval-grounded generation and an answer using generation without retrieval, judge each for relevance and for parameter-accuracy (correct, incorrect, or not stated, matched against the question's expected values), and report an aggregate accuracy comparison between the two conditions.

#### Scenario: A grounded and non-grounded answer are both judged
- **WHEN** LLM evaluation runs a ground-truth question
- **THEN** both a retrieval-grounded answer and a non-grounded answer are generated and judged, and each judgment records a relevance verdict and a parameter-accuracy verdict

#### Scenario: A deprecation question distinguishes grounded from non-grounded accuracy
- **WHEN** LLM evaluation runs a ground-truth deprecation question whose expected answer is "deprecated"
- **THEN** the grounded and non-grounded judgments are recorded separately, so a difference in correctness between the two conditions is visible in the results

### Requirement: Compositional task evaluation checks generated playbook tasks against real documentation
The system SHALL evaluate, for a fixed set of task-generation prompts drawn from the same named modules used for ground truth, whether the generated YAML is syntactically valid, whether every module and parameter name it uses actually exists in the ingested documentation, and whether every required parameter for a used module is present.

#### Scenario: A generated task is checked on all three dimensions
- **WHEN** compositional task evaluation runs a prompt
- **THEN** the result records whether the output YAML parses, whether all referenced module/parameter names exist in the ingested documentation, and whether all required parameters for the modules used are present

### Requirement: Evaluation results are viewable in the running application without regenerating them
The system SHALL display, on a dedicated page in the application, the currently persisted ground-truth set's generation metadata and the currently persisted evaluation results, reading them as previously generated rather than triggering new generation or evaluation runs, and SHALL show instructions for how to regenerate them outside the application.

#### Scenario: The evaluation page shows the pinned version and results
- **WHEN** a visitor opens the evaluation page
- **THEN** the page displays the `ansible-core` version and generation date the currently persisted ground truth is pinned to, the retrieval evaluation results, the LLM evaluation results, and the compositional evaluation results, without running any new generation or evaluation

#### Scenario: The evaluation page does not trigger regeneration
- **WHEN** a visitor opens the evaluation page
- **THEN** no ground truth is generated and no evaluation is executed as a result of that page load

#### Scenario: No persisted results exist yet
- **WHEN** a visitor opens the evaluation page before any ground truth or evaluation results have been generated
- **THEN** the page indicates that no results are available yet, instead of erroring
