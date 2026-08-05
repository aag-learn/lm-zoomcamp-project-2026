## Purpose

Gives reviewers and operators live visibility into real chat usage — query volume, latency, cost, retrieval confidence, and user feedback — via a pre-configured Grafana dashboard and a lightweight in-app summary, both reading from data the app already logs on every real chat turn.

## ADDED Requirements

### Requirement: Grafana dashboard is available with zero manual setup
The system SHALL provide a `grafana` service, reachable via `docker compose up`, that presents a fully populated monitoring dashboard immediately — without the operator manually configuring a data source or building any panel through the Grafana UI.

#### Scenario: Fresh stack, dashboard already populated
- **WHEN** an operator with no prior Grafana experience runs `docker compose up -d --build` on a completely fresh checkout and real chat traffic has occurred
- **THEN** logging into Grafana shows a dashboard with working panels sourced from the live database, with no manual data-source or panel configuration required

### Requirement: Grafana dashboard reflects live chat traffic
The system SHALL surface, via Grafana panels, at minimum: query volume over time, response latency, cost, user feedback ratio, and which modules are queried most — all derived from real chat interactions, not from offline evaluation data.

#### Scenario: New chat activity appears in the dashboard
- **WHEN** a new chat message is sent and answered, producing a new `RetrievalLog` and/or `Feedback` record
- **THEN** the relevant Grafana panels reflect this new data on their next refresh, without requiring an application restart

### Requirement: Grafana connects to the database with least-privilege, read-only access
The system SHALL configure Grafana's database connection to use credentials that grant only read access to the tables its panels query, distinct from the application's own read-write database credentials.

#### Scenario: Grafana's datasource cannot write
- **WHEN** a query is attempted through Grafana's configured datasource that would modify data (e.g. an `INSERT`, `UPDATE`, or `DELETE`)
- **THEN** the database rejects it due to insufficient privileges on that role

### Requirement: In-app monitoring summary is available in the chat application
The system SHALL provide a page within the Rails application, reachable via its own navigation entry, that shows a short summary of live usage metrics (at minimum: total queries, average response time, total cost, and feedback ratio) without requiring the operator to open Grafana.

#### Scenario: Summary reflects real usage
- **WHEN** an operator visits the in-app monitoring page after real chat traffic has occurred
- **THEN** the page shows non-zero, accurate summary figures computed from that traffic, along with a way to reach the full Grafana dashboard for more detail
