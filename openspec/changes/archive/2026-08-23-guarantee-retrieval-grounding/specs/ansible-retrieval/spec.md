## MODIFIED Requirements

### Requirement: Assistant replies can be grounded in retrieved documentation
The system SHALL search ingested Ansible module documentation on the first tool-call round of every real chat turn, and use the results to inform its reply, rather than leaving the decision to search up to the model's own judgment.

#### Scenario: A question resolvable from ingested docs triggers a search
- **WHEN** a visitor asks a question that requires specific Ansible module documentation (e.g. a parameter's default value)
- **THEN** the assistant's reply is generated using results retrieved from the ingested chunks, not only its own trained knowledge

#### Scenario: Search happens even when the model believes it already knows the answer
- **WHEN** a visitor asks about a well-known module the model could plausibly answer from its own training data (e.g. a common parameter default)
- **THEN** the assistant's tool-calling round is forced to invoke the search tool first, rather than the model skipping straight to a direct answer or an exact-module lookup

### Requirement: Every retrieval-grounded reply is logged
The system SHALL record, for every assistant reply, which chunks were retrieved (if any), a primary source module (if any), and the reply's cost and response time — regardless of whether the retrieved results were relevant.

#### Scenario: Log entry created alongside the reply
- **WHEN** an assistant reply is generated using retrieval
- **THEN** a log entry is created associated with that reply, recording the retrieved chunk identifiers, a primary/top module, cost, and response time

#### Scenario: A log entry is created even when retrieval finds nothing relevant
- **WHEN** an assistant reply is generated for a turn where the search tool was invoked but returned no relevant results (e.g. a non-Ansible question)
- **THEN** a log entry is still created for that reply, with the low-relevance retrieved chunks recorded honestly, rather than being omitted
