## Why

`rails_app/config/database.yml`'s `development`/`test` blocks are still Rails' generated defaults — no `host`/`port`/`username`/`password` — which assumes a locally-installed Postgres reachable over a Unix socket with peer auth. That never actually applies here: this project's Postgres always runs in the `docker-compose`/`podman-compose` container, published on `localhost:${POSTGRES_PORT:-5432}`, requiring the real password over TCP. In practice this meant every local `bin/rails` command had to be prefixed with a manually-typed `DATABASE_URL=...`, discovered as friction during the `ansible-ingestion-pipeline` implementation session.

## What Changes

- Add `host`, `port`, `username`, `password` to the `development` and `test` blocks in `rails_app/config/database.yml`, mirroring the `production` block's shape but pointed at `localhost` (a local process talking to the container's published port) instead of `production`'s `postgres` (container-to-container over the compose network alias).
- `username`/`password` read via `ENV.fetch` with a default matching `.env.example`'s placeholder values (`llm_zoomcamp`/`changeme`), not a no-default `ENV["..."]` read — so a fresh clone's local dev/test databases work with zero shell configuration, while still respecting an explicit override.
- `port` reads via `ENV.fetch("POSTGRES_PORT", 5432)`, matching the `<SERVICE>_PORT` convention already used in `docker-compose.yml`.
- `production`'s block is unchanged — already correct.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `postgres-database`: adds a requirement that local (non-containerized) Rails commands can connect to the development and test databases without additional environment configuration beyond what a fresh clone already has.

## Impact

- **Modified**: `rails_app/config/database.yml` (`development`/`test` blocks only).
- **No changes to**: `docker-compose.yml`, `production`'s database config, any container image.
