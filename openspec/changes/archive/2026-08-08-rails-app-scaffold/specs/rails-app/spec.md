## Purpose

A single Rails codebase that builds into two distinct container images — a web-serving process and a background-job-processing process — so every later capability (ingestion, retrieval, chat) has a running application to live in.

## ADDED Requirements

### Requirement: Web container serves an HTTP health endpoint
The system SHALL provide a `web` container that boots a Rails HTTP server and responds successfully to a health-check request without requiring any application-specific code.

#### Scenario: Web container reaches healthy
- **WHEN** the `web` service is started via `docker compose up -d web`
- **THEN** it reaches a healthy status once the Rails server responds successfully to its health endpoint

### Requirement: Worker container runs a background job processor
The system SHALL provide a `worker` container, built from the same codebase as `web`, that runs a background job processor capable of connecting to its job-queue database and polling for work.

#### Scenario: Worker starts without crashing
- **WHEN** the `worker` service is started via `docker compose up -d` after the application's databases have been prepared
- **THEN** its process starts and begins polling for jobs without crash-looping on a missing schema or failed database connection

### Requirement: Application databases are prepared automatically
The system SHALL prepare the application's databases (creating and migrating them if they don't already exist) automatically as part of `docker compose up`, without requiring the operator to manually run a database-preparation command.

#### Scenario: Fresh stack, no manual step required
- **WHEN** an operator with no prior knowledge of Rails runs `docker compose up -d --build` on a completely fresh checkout (databases do not yet exist)
- **THEN** the databases are created and migrated automatically, and both `web` and `worker` start successfully without the operator running any database-preparation command themselves

#### Scenario: Database preparation does not race
- **WHEN** `web` and `worker` are both starting around the same time
- **THEN** database preparation happens exactly once, completing before either `web` or `worker` starts, not concurrently from multiple processes

### Requirement: Worker container can invoke ansible-doc
The system SHALL ensure the `worker` container has `ansible-core` installed, independent of any Ruby code, so `ansible-doc` can be invoked directly inside it.

#### Scenario: Direct ansible-doc invocation succeeds
- **WHEN** `ansible-doc -j <module>` is run directly inside a running `worker` container (e.g. via `docker compose exec`)
- **THEN** it returns valid JSON module documentation, with no Ruby code involved

### Requirement: Web and worker build from a single codebase
The system SHALL build both the `web` and `worker` container images from the same Rails codebase and the same build context, differing only in their installed dependencies (`worker` additionally has `ansible-core`) and their startup command.

#### Scenario: Shared codebase, distinct images
- **WHEN** both `web` and `worker` images are built
- **THEN** both are built from the same repository content, and neither requires a separate Rails application or a separate `Gemfile`
