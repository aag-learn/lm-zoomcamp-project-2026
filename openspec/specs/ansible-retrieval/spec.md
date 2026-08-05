## Purpose

Ground the chat's answers in the ingested `ansible.builtin` documentation via hybrid+reranked retrieval exposed to the agent as tools, with every grounded reply logged and cited — turning the chat from free-recall into a real retrieval-augmented assistant.

## Requirements

### Requirement: Assistant replies can be grounded in retrieved documentation
The system SHALL search ingested Ansible module documentation on the first tool-call round of every real chat turn, and use the results to inform its reply, rather than leaving the decision to search up to the model's own judgment.

#### Scenario: A question resolvable from ingested docs triggers a search
- **WHEN** a visitor asks a question that requires specific Ansible module documentation (e.g. a parameter's default value)
- **THEN** the assistant's reply is generated using results retrieved from the ingested chunks, not only its own trained knowledge

#### Scenario: Search happens even when the model believes it already knows the answer
- **WHEN** a visitor asks about a well-known module the model could plausibly answer from its own training data (e.g. a common parameter default)
- **THEN** the assistant's tool-calling round is forced to invoke the search tool first, rather than the model skipping straight to a direct answer or an exact-module lookup

### Requirement: Retrieval combines keyword and semantic search
The system SHALL combine full-text keyword search and vector similarity search results into a single ranked list when searching Ansible documentation.

#### Scenario: Results reflect both keyword and semantic matches
- **WHEN** a search retrieves chunks
- **THEN** the returned set reflects both keyword-search results and vector-similarity-search results merged into one ranking, not either search executed alone

### Requirement: Retrieved candidates are reranked
The system SHALL rerank the top retrieval candidates against the original query before they are used to ground a reply.

#### Scenario: Reranking can reorder the initial hybrid ranking
- **WHEN** retrieval returns an initial hybrid-ranked set of candidates
- **THEN** those candidates are reranked against the query, and the final order used for grounding can differ from the initial hybrid ranking

### Requirement: The agent can fetch full parameter details for a specific module
The system SHALL allow the assistant to request the complete documentation for one exact, named Ansible module, independent of search ranking.

#### Scenario: Exact module lookup
- **WHEN** the assistant has identified a specific module by its fully-qualified name
- **THEN** it can retrieve that module's complete parameter/example/return documentation directly, not only search-ranked fragments

### Requirement: Every retrieval-grounded reply is logged
The system SHALL record, for every assistant reply, which chunks were retrieved (if any), a primary source module (if any), and the reply's cost and response time — regardless of whether the retrieved results were relevant.

#### Scenario: Log entry created alongside the reply
- **WHEN** an assistant reply is generated using retrieval
- **THEN** a log entry is created associated with that reply, recording the retrieved chunk identifiers, a primary/top module, cost, and response time

#### Scenario: A log entry is created even when retrieval finds nothing relevant
- **WHEN** an assistant reply is generated for a turn where the search tool was invoked but returned no relevant results (e.g. a non-Ansible question)
- **THEN** a log entry is still created for that reply, with the low-relevance retrieved chunks recorded honestly, rather than being omitted

### Requirement: Retrieved sources are cited in the interface
The system SHALL make retrieval source information available for each retrieval-grounded assistant reply, on demand rather than automatically displayed as an inline claim — see the `chat-interface` capability's "Retrieval details are available on demand, not auto-displayed" requirement for the exact mechanism.

#### Scenario: Citations visible under a grounded reply
- **WHEN** a visitor activates the retrieval-details affordance on an assistant reply that used retrieval
- **THEN** the source module(s) the reply was grounded in are shown, without being auto-displayed as an unqualified claim alongside the reply
