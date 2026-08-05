## 1. Update database.yml

- [x] 1.1 Add `host: localhost`, `port: <%= ENV.fetch("POSTGRES_PORT", 5432) %>`, `username: <%= ENV.fetch("POSTGRES_USER", "llm_zoomcamp") %>`, `password: <%= ENV.fetch("POSTGRES_PASSWORD", "changeme") %>` to the `development` block
- [x] 1.2 Add the same four keys to the `test` block
- [x] 1.3 Confirm `production`'s block is untouched

## 2. Verify

- [x] 2.1 With the `postgres` service running and no `DATABASE_URL`/`POSTGRES_*` variables set in the shell, run `bin/rails db:prepare` (or equivalent) locally and confirm it connects successfully to `rails_app_development` — confirmed; `db:prepare` also created/prepared `rails_app_test` in the same run (Rails' default `maintain_test_schema` behavior)
- [x] 2.2 Under the same zero-configuration conditions, run `bin/rails test` locally and confirm it connects successfully to `rails_app_test` — confirmed; all 24 tests pass with zero env vars set
- [x] 2.3 With `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_PORT` explicitly exported to different values than the defaults, confirm a local Rails command uses those values instead (e.g. fails to connect if they're wrong, proving the override isn't ignored) — confirmed; `POSTGRES_PASSWORD=definitely_wrong` produced `PG::ConnectionBad: password authentication failed for user "llm_zoomcamp"`, proving the override reached the connection, not the hardcoded default
- [x] 2.4 Confirm `docker compose`/`podman-compose`-driven flows (`prepare_db`, `web`, `worker`) are unaffected — they don't read `development`/`test`, only `production` — confirmed against the real running `worker` container (`RAILS_ENV=production`), still connects fine: 71 modules, 1538 chunks readable, no regression
