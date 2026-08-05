## ADDED Requirements

### Requirement: Read-only reporting role is provisioned automatically
The system SHALL provision a dedicated Postgres role with read-only access to the tables monitoring tools need, automatically as part of application startup, without requiring the operator to run any manual SQL command — on both a fresh database and one that already existed before this role was introduced.

#### Scenario: Fresh stack, reporting role exists
- **WHEN** `docker compose up` is run against a completely fresh Postgres volume with a valid `.env` file present
- **THEN** a dedicated read-only role exists in the database once `web` or `worker` has started, with `SELECT` access to the tables monitoring tools need and no write access

#### Scenario: Existing database is reconciled too
- **WHEN** `docker compose up` is run against a Postgres volume that was already initialized before this role existed
- **THEN** the role is created automatically the next time `web` or `worker` starts, without any manual SQL command from the operator

#### Scenario: Provisioning is idempotent
- **WHEN** `web` and `worker` both start (or restart) against a database where the role already exists
- **THEN** provisioning completes without error, and does not fail or duplicate the role
