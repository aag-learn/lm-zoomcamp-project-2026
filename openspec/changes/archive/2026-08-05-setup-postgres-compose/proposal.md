## Why

The project (per `PLAN.md`) needs a Postgres database with `pgvector` (vector similarity search for embeddings) and full-text search (`tsvector`/GIN) support, both living in the same `chunks` table. This is the first infrastructure piece needed before any ingestion, retrieval, or Rails app code can be written, and it should be provisionable via `docker compose up` with no manual DB setup, keeping credentials out of source control via a `.env` file.

## What Changes

- Add a `docker-compose.yml` at the repo root defining a `postgres` service using a `pgvector`-enabled Postgres image.
- Add a `.env.example` documenting the required environment variables (db name, user, password, port) with placeholder values.
- Add a `.env` entry to `.gitignore` so real credentials are never committed.
- Configure the compose service to read `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` from `.env` (via `env_file` or `environment` with variable substitution).
- Add a healthcheck so dependent services (Rails app, worker, added in later changes) can wait on Postgres readiness.
- Add a named volume for data persistence across `docker compose down`/`up` cycles.
- Ensure the `vector` extension is available for later migrations to `CREATE EXTENSION vector;` (image-level support, not the migration itself — that lands with the Rails app in a later change).

## Capabilities

### New Capabilities
- `postgres-database`: Containerized Postgres service (via Docker Compose) with `pgvector` extension support and full-text search (`tsvector`/GIN) capability, configured entirely through environment variables sourced from a `.env` file.

### Modified Capabilities
(none — this is the first change in the project)

## Impact

- **Affected files**: new `docker-compose.yml`, new `.env.example`, new/updated `.gitignore`.
- **Dependencies**: requires a `pgvector`-enabled Postgres Docker image (e.g. `pgvector/pgvector:pg18` or `ankane/pgvector`).
- **Systems**: this is the foundation the Rails app, migrations (`neighbor`/`pgvector` gems), and later ingestion job will connect to. No application code depends on it yet, so no breaking changes.
