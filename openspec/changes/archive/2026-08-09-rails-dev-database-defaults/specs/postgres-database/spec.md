## ADDED Requirements

### Requirement: Local Rails commands connect to development/test databases without extra configuration
The system SHALL configure the Rails application's `development` and `test` database connections (host, port, username, password) such that a local, non-containerized `bin/rails` command can connect to the running Postgres container's published port using only the default values already documented in `.env.example`, without requiring the operator to set any additional environment variable.

#### Scenario: A local Rails command connects with a fresh clone's defaults
- **WHEN** a contributor with a fresh clone, `.env.example`'s values, and the `postgres` service running via `docker compose up -d postgres` runs a local `bin/rails` command (e.g. `bin/rails db:prepare` or `bin/rails console`) without setting `DATABASE_URL` or any `POSTGRES_*` variable in their shell
- **THEN** the command connects successfully to the development database on the container's published port

#### Scenario: An explicit environment override still takes effect
- **WHEN** a contributor sets `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_PORT` in their shell to values different from `.env.example`'s defaults (e.g. because their running Postgres container was started with different credentials)
- **THEN** the local Rails command connects using those explicitly-set values, not the built-in defaults

#### Scenario: The test database connects the same way
- **WHEN** a contributor runs `bin/rails test` locally without setting any environment variable
- **THEN** it connects successfully to the test database on the same running Postgres container, using the same default credentials
