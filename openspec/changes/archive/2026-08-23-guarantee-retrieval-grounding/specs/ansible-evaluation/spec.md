## MODIFIED Requirements

### Requirement: LLM evaluation compares RAG-grounded and non-grounded answers
The system SHALL, for each ground-truth question, generate an answer using retrieval-grounded generation (with the search tool forced on the first round, so retrieval is actually exercised rather than left to the model's discretion) and an answer using generation without retrieval, judge each for relevance and for parameter-accuracy (correct, incorrect, or not stated, matched against the question's expected values), and report an aggregate accuracy comparison between the two conditions.

#### Scenario: A grounded and non-grounded answer are both judged
- **WHEN** LLM evaluation runs a ground-truth question
- **THEN** both a retrieval-grounded answer and a non-grounded answer are generated and judged, and each judgment records a relevance verdict and a parameter-accuracy verdict

#### Scenario: A deprecation question distinguishes grounded from non-grounded accuracy
- **WHEN** LLM evaluation runs a ground-truth deprecation question whose expected answer is "deprecated"
- **THEN** the grounded and non-grounded judgments are recorded separately, so a difference in correctness between the two conditions is visible in the results

#### Scenario: The RAG condition always exercises real retrieval
- **WHEN** LLM evaluation generates the retrieval-grounded answer for a question
- **THEN** the search tool is invoked on the first round regardless of whether the model would have chosen to call it on its own, so the RAG-vs-non-RAG comparison measures actual retrieval quality rather than the model's own decision of whether to search
