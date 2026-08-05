## Purpose

Ground the chat's answers in the ingested `ansible.builtin` documentation via hybrid+reranked retrieval exposed to the agent as tools, with every grounded reply logged and cited — turning the chat from free-recall into a real retrieval-augmented assistant.

## ADDED Requirements

### Requirement: Assistant replies can be grounded in retrieved documentation
The system SHALL give the assistant the ability to search ingested Ansible module documentation and use the results to inform its reply.

#### Scenario: A question resolvable from ingested docs triggers a search
- **WHEN** a visitor asks a question that requires specific Ansible module documentation (e.g. a parameter's default value)
- **THEN** the assistant's reply is generated using results retrieved from the ingested chunks, not only its own trained knowledge

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
The system SHALL record, for every assistant reply generated using retrieval, which chunks were retrieved, a primary source module, and the reply's cost and response time.

#### Scenario: Log entry created alongside the reply
- **WHEN** an assistant reply is generated using retrieval
- **THEN** a log entry is created associated with that reply, recording the retrieved chunk identifiers, a primary/top module, cost, and response time

### Requirement: Retrieved sources are cited in the interface
The system SHALL display, for each retrieval-grounded assistant reply, which source documentation it was based on.

#### Scenario: Citations visible under a grounded reply
- **WHEN** a visitor views an assistant reply that used retrieval
- **THEN** the source module(s) the reply was grounded in are visibly displayed alongside that reply
