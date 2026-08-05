## 1. Groundwork (verify before building on top of assumptions)

- [x] 1.1 Confirm what healthcheck tooling is available inside the official `grafana/grafana` image (Alpine-based). **Confirmed: both `wget` and `curl` present (`/usr/bin/wget`, `/usr/bin/curl`), Grafana 13.2.0 on Alpine 3.24.1. Will use `wget --spider` against `/api/health`.**
- [x] 1.2 Confirm the exact Grafana provisioning YAML syntax for env-var substitution of a datasource password. **Confirmed live: `$VAR`-style substitution works for provisioning YAML values (tested with an isolated throwaway container — a `url: $TEST_SUBSTITUTION_HOST:5432` field came back correctly substituted via the Grafana API). `type: postgres` also confirmed to resolve correctly to the bundled `grafana-postgresql-datasource` plugin. Using `secureJsonData.password: $GRAFANA_DB_PASSWORD` per the image's own bundled `sample.yaml`.**
- [x] 1.3 Confirm the read-only `grafana/dashboards` bind mount coexists correctly with the writable `grafana_data` named volume at `/var/lib/grafana` under podman specifically. **Confirmed live: nested mount works exactly as intended — `/var/lib/grafana` writable (grafana.db created fine), `/var/lib/grafana/dashboards` genuinely read-only (`touch` fails with "Read-only file system"), file still readable.**

## 2. Rails: read-only reporting role

- [x] 2.1 Write `rails_app/lib/tasks/grafana.rake` with a `db:grafana_reader:ensure` task: creates the `grafana_reader` role (password from `ENV.fetch("GRAFANA_DB_PASSWORD")`) via `ActiveRecord::Base.connection.execute`, rescuing the "role already exists" case; grants `SELECT` on `retrieval_logs`, `feedbacks`, `messages` on the primary database (add `chats` only if a panel from Group 4 ends up needing it) — grants are naturally idempotent, no rescue needed there.
- [x] 2.2 Add a call to `bin/rails db:grafana_reader:ensure` in `rails_app/bin/docker-entrypoint`, right after `bin/rails db:prepare`.
- [x] 2.3 Add `GRAFANA_DB_PASSWORD` to `web`'s and `worker`'s `environment:` blocks in `docker-compose.yml` (both run the entrypoint, so both need it).

## 3. Secrets

- [x] 3.1 Add `GRAFANA_ADMIN_PASSWORD`, `GRAFANA_DB_PASSWORD`, and `GRAFANA_PORT` to `.env.example` with `changeme` placeholders and explanatory comments, matching the existing style.
- [x] 3.2 Add the same three values to the local `.env` (not committed) for this session's own testing.

## 4. Grafana provisioning

- [x] 4.1 Write `grafana/provisioning/datasources/postgres.yml` — declares the Postgres datasource pointing at `postgres:5432`, using `grafana_reader`/`$GRAFANA_DB_PASSWORD`. Gave it an explicit fixed `uid: postgres_grafana_reader` so the dashboard JSON can reference it deterministically rather than an auto-generated UID.
- [x] 4.2 Write `grafana/provisioning/dashboards/dashboards.yml` — dashboard-provider config pointing at the dashboards folder, `allowUiUpdates: false`.
- [x] 4.3 Write `grafana/dashboards/chat-monitoring.json` with 6 panels: query volume/day, latency p50/p95/day, cost/day + running total, feedback ratio/day, top modules queried, low-confidence-retrieval rate/day — each as a raw SQL panel against `retrieval_logs`/`feedbacks`, using `$__timeFilter`/`$__timeGroup` macros. JSON validated well-formed.

## 5. Compose wiring

- [x] 5.1 Add the `grafana` service to `docker-compose.yml`: image, `GF_SECURITY_ADMIN_PASSWORD` from `$GRAFANA_ADMIN_PASSWORD`, `${GRAFANA_PORT:-3001}:3000` port mapping, the two `:ro` provisioning/dashboard bind mounts (task 4), a writable `grafana_data` named volume at `/var/lib/grafana`, `depends_on: postgres: condition: service_healthy`, and a `wget --spider` healthcheck against `/api/health`.
- [x] 5.2 Add `grafana_data` to the top-level `volumes:` block.

## 6. In-app Monitoring page

- [x] 6.1 Add a `MonitoringsController#show` with 4 aggregate queries: total queries (`RetrievalLog.count`), avg response time, total cost, feedback ratio (`Feedback` thumbs up / total). **Note: named `MonitoringsController` (plural), not `MonitoringController` — Rails' singular `resource :monitoring` route still pluralizes the expected controller class name by convention, exactly like the existing `resource :evaluation` → `EvaluationsController`. Caught by the test suite, not assumed.**
- [x] 6.2 Add the corresponding view: 4 stat cards, plus a link to the Grafana URL. Surfaced via `GRAFANA_PORT` passed through to `web`'s environment in `docker-compose.yml` (it wasn't previously — added it) so the in-app link reflects the operator's actual chosen port, not just the compiled-in default.
- [x] 6.3 Add the route and a new nav entry, matching the existing pattern used for the evaluation-results page.
- [x] 6.4 Add a minimal controller test. Passes: `2 runs, 6 assertions, 0 failures, 0 errors`. Rubocop clean on all new files (controller, test, `grafana.rake`).

## 7. Verification

- [x] 7.1 Restart `web`/`worker` against this session's already-existing dev `postgres_data` volume and confirm `grafana_reader` gets created automatically (no manual `psql` step needed — this is the point of the Rake-task approach over a first-boot-only script). **Confirmed live: worker logs showed "Created grafana_reader role" / "Granted SELECT..."; `\du grafana_reader` and `\z retrieval_logs` confirmed the role and grant exist in the real, pre-existing dev database — zero manual psql step.**
- [x] 7.2 Fresh-volume test, isolated project (`freshtest`, distinct ports set via temporarily-edited `.env` — exported shell vars were silently ignored by podman-compose, a new quirk worth noting; `.env` restored byte-identical afterward). **Confirmed on a genuinely fresh volume: schema created via db:prepare, `grafana_reader` role + all three grants present, Grafana's datasource and 6-panel dashboard auto-provisioned with zero manual steps. Also found and fixed a real bug: `GRAFANA_DB_PASSWORD` was never added to the `grafana` service's own `environment:` block in docker-compose.yml (only to web/worker) — Grafana's own provisioning-time `$VAR` substitution needs it directly. Fixed and re-verified; also applied the fix to the real running stack's `grafana` container.** Also directly reproduced, live, the known `db:prepare` fresh-volume race documented in `rework-startup-dependencies`'s design.md (`web` crashed once with `solid_queue_blocked_executions does not exist`) — recovered cleanly via the documented remediation (restart), confirming that prior design's risk analysis was accurate.
- [x] 7.3 Confirm Grafana rejects a write attempt through its datasource (least-privilege check). **Confirmed: `INSERT` through the datasource returns `permission denied for table feedbacks (SQLSTATE 42501)`.**
- [x] 7.4 Send a real chat message end-to-end and confirm the new `RetrievalLog`/`Feedback` rows appear in both the Grafana panels (on refresh) and the in-app Monitoring page. **Confirmed (fresh volume had no ingested corpus, so used a direct row creation to isolate the monitoring plumbing itself rather than re-testing retrieval quality, which the eval pipeline already covers exhaustively) — both the in-app page and a live Grafana panel query reflected the new row.**
- [x] 7.5 Confirm the `:ro` mounts behave as expected: creating a brand-new dashboard via the Grafana UI succeeds (saved to internal state, not the mounted files); the repo's `grafana/dashboards/chat-monitoring.json` is untouched afterward. **Confirmed via Grafana's API (UI-equivalent): new dashboard created successfully, `chat-monitoring.json`'s md5 unchanged before/after.**
- [x] 7.6 Confirm provisioning is idempotent: restart `web`/`worker` again against a database where `grafana_reader` already exists, and confirm no error. **Confirmed: worker logs show the rescue path firing cleanly ("grafana_reader role already exists") on restart.**
- [x] 7.7 `openspec validate monitoring-dashboard --type change --strict`.
- [x] 7.8 Fix, reported by the user after initial apply via a screenshot: every panel showed "You do not currently have a default database configured for this data source." Root cause and fix documented in design.md's "Verified after initial apply" — added `database: rails_app_production` under `jsonData` in `grafana/provisioning/datasources/postgres.yml` (the top-level `database:` field alone was sufficient for query execution but not for the dashboard UI's own configured-database check). Verified live on the real dev stack: warning cleared, all 4 existing `retrieval_logs` rows now render.
