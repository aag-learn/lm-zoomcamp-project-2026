## MODIFIED Requirements

### Requirement: Application databases are prepared automatically
The system SHALL prepare the application's databases (creating and migrating them if they don't already exist) automatically as part of `docker compose up`, without requiring the operator to manually run a database-preparation command.

#### Scenario: Fresh stack, no manual step required
- **WHEN** an operator with no prior knowledge of Rails runs `docker compose up -d --build` on a completely fresh checkout (databases do not yet exist)
- **THEN** the databases are created and migrated automatically, and both `web` and `worker` start successfully without the operator running any database-preparation command themselves

#### Scenario: Database preparation does not race
- **WHEN** `web` and `worker` both prepare their own databases as part of starting up
- **THEN** database preparation never runs concurrently from both containers against a fresh database — one container's startup ordering guarantees it always completes database preparation before the other begins its own

### Requirement: Worker container runs a background job processor
The system SHALL provide a `worker` container, built from the same codebase as `web`, that runs a background job processor capable of connecting to its job-queue database and polling for work, and that reports its own health based on whether it is actively processing.

#### Scenario: Worker starts without crashing
- **WHEN** the `worker` service is started via `docker compose up -d`
- **THEN** its process starts, prepares its own databases if needed, and begins polling for jobs without crash-looping on a missing schema or failed database connection

#### Scenario: Worker reports healthy only once actively processing
- **WHEN** the `worker` container's job processor has recorded a recent heartbeat
- **THEN** the container's healthcheck reports healthy; before that heartbeat exists (e.g. still preparing its database or booting), it reports unhealthy

## ADDED Requirements

### Requirement: Web container waits for a healthy worker before starting
The system SHALL NOT start the `web` container until the `worker` container is reporting healthy, so that a broken or not-yet-ready worker is visible as a fully down stack rather than a `web` container that silently accepts requests it cannot fulfill (e.g. chat messages that will never receive a reply).

#### Scenario: Worker unhealthy blocks web from starting
- **WHEN** the `worker` container fails to become healthy (e.g. it cannot connect to its database or crashes on boot)
- **THEN** the `web` container does not start

#### Scenario: Worker healthy allows web to start
- **WHEN** the `worker` container reports healthy
- **THEN** the `web` container is started
