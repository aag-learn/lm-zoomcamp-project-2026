## ADDED Requirements

### Requirement: Containerized Postgres service
The system SHALL provide a `postgres` service defined in `docker-compose.yml` that runs a Postgres image capable of supporting the `pgvector` extension.

#### Scenario: Service starts via docker compose
- **WHEN** an operator runs `docker compose up -d postgres` with a valid `.env` file present
- **THEN** a Postgres container starts and becomes healthy without any manual database setup steps

#### Scenario: pgvector extension is available
- **WHEN** a client connects to the running database and executes `CREATE EXTENSION IF NOT EXISTS vector;`
- **THEN** the statement succeeds, confirming the image ships the `pgvector` extension

### Requirement: Full-text search support
The system SHALL support Postgres full-text search (`tsvector` columns and GIN indexes) without requiring any additional extension beyond the base Postgres installation.

#### Scenario: tsvector column and GIN index can be created
- **WHEN** a client executes `CREATE TABLE` with a `tsvector` column and a `CREATE INDEX ... USING GIN` statement against that column
- **THEN** both statements succeed using only built-in Postgres functionality

### Requirement: Credentials sourced from environment variables
The system SHALL configure the Postgres service's user, password, and database name exclusively via environment variables, with no credentials hardcoded in `docker-compose.yml`.

#### Scenario: Compose file references env vars
- **WHEN** `docker-compose.yml` is inspected
- **THEN** `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` appear only as `${VAR}` references, never as literal values

#### Scenario: Missing password fails loudly
- **WHEN** `docker compose up postgres` is run without `POSTGRES_PASSWORD` set (no `.env` file, or the variable absent from it)
- **THEN** the compose command fails or refuses to start the service with an unset/blank password, rather than silently starting with a blank password

### Requirement: .env file drives configuration, .env.example documents it
The system SHALL read runtime configuration from a `.env` file at the repo root (auto-loaded by Docker Compose) and SHALL provide a tracked `.env.example` file documenting every required variable with placeholder values.

#### Scenario: .env is gitignored
- **WHEN** `git status` is run after creating a real `.env` file with actual credentials
- **THEN** `.env` does not appear as a trackable/untracked file, because it is listed in `.gitignore`

#### Scenario: .env.example lists all required variables
- **WHEN** a new contributor inspects `.env.example`
- **THEN** they find every environment variable the `postgres` service needs (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT`) with placeholder or sensible default values and no real secrets

### Requirement: Data persistence across container restarts
The system SHALL persist Postgres data in a named Docker volume so that data survives `docker compose down` (without the `-v` flag) and subsequent `docker compose up`.

#### Scenario: Data survives a restart
- **WHEN** data is written to the database, then `docker compose down` followed by `docker compose up -d postgres` is run
- **THEN** the previously written data is still present and queryable

### Requirement: Healthcheck for dependent services
The system SHALL define a healthcheck on the `postgres` service that reports healthy only once the database is ready to accept connections, so other compose services can declare a `depends_on` condition on it.

#### Scenario: Healthcheck reflects readiness
- **WHEN** the `postgres` container has just started and is still initializing
- **THEN** `docker compose ps` reports its health status as starting/unhealthy until the database is actually ready to accept connections, after which it reports healthy
