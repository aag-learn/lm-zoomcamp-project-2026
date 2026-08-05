## Why

PLAN.md's Monitoring rubric category ("feedback AND 5+ chart dashboard") is the last major uncovered category — `RetrievalLog` (cost, response_time, tokens, top_module, per-chunk rerank_score) and `Feedback` (thumbs up/down, already live in the chat UI) have been written on every real chat turn since the retrieval-wiring change, but nothing reads or visualizes that data yet. The user wants Grafana as the primary dashboard (as used in the LLM Zoomcamp course itself), with a lightweight in-app summary alongside it.

## What Changes

- Add a `grafana` service to `docker-compose.yml`, backed by a git-tracked, provisioning-as-code setup (datasource + dashboard JSON auto-loaded on boot) rather than the course's manual click-through UI setup — so a reviewer gets a fully populated dashboard immediately on `docker compose up`, with zero manual configuration steps, consistent with every other service in this project.
- Add a dedicated read-only Postgres role (`grafana_reader`) for Grafana's datasource, provisioned by a new idempotent Rake task (`db:grafana_reader:ensure`) invoked from `rails_app/bin/docker-entrypoint` right after `db:prepare`, rather than reusing the app's own read-write `POSTGRES_USER`/`POSTGRES_PASSWORD`. The Rails app owns this the same way it owns all other database setup — a plain Postgres-side init script was considered and rejected (see design.md).
- Add two new required `.env`/`.env.example` secrets: `GRAFANA_ADMIN_PASSWORD` (Grafana's own admin login) and `GRAFANA_DB_PASSWORD` (the `grafana_reader` role's password), following this project's existing `${VAR:?must be set in .env}` pattern.
- Add a new `GRAFANA_PORT` env var following the existing `<SERVICE>_PORT` convention.
- Ship 6 Grafana panels sourced entirely from already-logged live chat data: query volume/day, latency p50/p95/day, cost/day + running total, feedback ratio/day, top modules queried, low-confidence-retrieval rate/day.
- Add a lightweight in-app "Monitoring" page (new controller, own nav entry, no new gems) showing 4 summary stat cards (total queries, avg response time, total cost, feedback ratio) with a pointer to the full Grafana dashboard — deliberately not a duplicate of Grafana's charts.
- **Scope decision, not a bug**: PLAN.md's originally-planned "LLM-judge verdict distribution" chart is dropped — it assumed live per-message judging, which doesn't exist (judges currently only run inside the offline `eval:llm` rake task). Feedback (thumbs up/down) remains the live quality signal for Monitoring; judges stay an eval-only concept, preserving the existing Monitoring-vs-Evaluation distinction already established in this project.

## Capabilities

### New Capabilities
- `monitoring`: the `grafana` compose service and its provisioning-as-code setup, the 6 live-traffic dashboard panels, and the in-app Monitoring summary page.

### Modified Capabilities
- `postgres-database`: gains a new requirement — a dedicated, read-only `grafana_reader` role is auto-provisioned by the Rails app on every boot (not just first-init), parallel to the existing "Credentials sourced from environment variables" requirement.

## Impact

- `docker-compose.yml`: new `grafana` service; `web`/`worker` services gain a new `GRAFANA_DB_PASSWORD` env var (needed by the new Rake task, which runs from their shared entrypoint).
- New files: `grafana/provisioning/datasources/postgres.yml`, `grafana/provisioning/dashboards/dashboards.yml`, `grafana/dashboards/chat-monitoring.json`, `rails_app/lib/tasks/grafana.rake`.
- `rails_app/bin/docker-entrypoint`: gains a call to `bin/rails db:grafana_reader:ensure` after `db:prepare`.
- `.env.example`: three new documented variables (`GRAFANA_ADMIN_PASSWORD`, `GRAFANA_DB_PASSWORD`, `GRAFANA_PORT`).
- `rails_app/`: new controller + view + route + nav entry for the in-app Monitoring page (pattern matches the existing `EvaluationsController#show`). No new gems, no new `ActiveRecord` model for the dashboard itself — reads `RetrievalLog`/`Feedback` directly via aggregate queries.
- `openspec/specs/postgres-database/spec.md`: one new requirement, delta-applied.
- No changes to the actual chat/retrieval/ingestion code paths — this change is purely additive, visualizing data that's already being written.
