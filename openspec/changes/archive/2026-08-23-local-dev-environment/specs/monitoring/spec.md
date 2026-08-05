## ADDED Requirements

### Requirement: Local dev chat traffic is visible in Grafana
The system SHALL provide a second Grafana datasource pointing at the `development` database (same Postgres container, same `grafana_reader` role, different database), and the Chat Monitoring dashboard SHALL expose a datasource-picker variable so an operator can switch between production and local dev traffic without needing a second dashboard.

#### Scenario: Switching the dashboard to dev data
- **WHEN** an operator viewing the Chat Monitoring dashboard changes the "Data source" variable from "Postgres" to "Postgres (dev)"
- **THEN** all panels re-query against the `development` database and show local `bin/dev` chat traffic, with no change to what the default (production) view shows when the variable is left at its default

#### Scenario: Dev datasource connects successfully out of the box
- **WHEN** `mise run db:prepare` has been run locally (which also runs `db:grafana_reader:ensure` against the `development` database)
- **THEN** Grafana's dev datasource health check succeeds against `rails_app_development` with no additional manual grant step
