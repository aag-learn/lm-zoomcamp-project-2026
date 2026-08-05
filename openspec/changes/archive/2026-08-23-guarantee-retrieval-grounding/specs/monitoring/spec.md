## MODIFIED Requirements

### Requirement: Grafana dashboard reflects live chat traffic
The system SHALL surface, via Grafana panels, at minimum: query volume over time, response latency, cost, user feedback ratio, and which modules are queried most — derived from ALL real chat interactions, not only ones where retrieval happened to find relevant results, and not from offline evaluation data.

#### Scenario: New chat activity appears in the dashboard
- **WHEN** a new chat message is sent and answered, producing a new `RetrievalLog` and/or `Feedback` record
- **THEN** the relevant Grafana panels reflect this new data on their next refresh, without requiring an application restart

#### Scenario: A reply with no relevant retrieval still counts toward volume/cost/latency
- **WHEN** a chat message is sent and answered, but the search tool found nothing relevant to the question (e.g. small talk unrelated to Ansible)
- **THEN** that turn still counts toward the dashboard's query volume, cost, and latency panels, since a `RetrievalLog` row is created for every real exchange regardless of retrieval relevance
