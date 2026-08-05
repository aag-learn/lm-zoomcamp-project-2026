## Context

See proposal.md for motivation. Data already exists and is already populated on every real chat turn — nothing here adds new instrumentation:

- `RetrievalLog` (one row per assistant message that used retrieval): `cost`, `response_time`, `input_tokens`, `output_tokens`, `top_module`, `retrieved_chunks` (jsonb array of `{stable_id, rrf_score, rerank_score}`), `ansible_core_version`, `created_at`.
- `Feedback` (`belongs_to :message`): `rating` (+1/-1).

Modeled on the LLM Zoomcamp course's own module 5 (`compose.yaml`, `module-5.ipynb`, read directly for this design): Postgres + Grafana, Grafana panels as raw SQL against the app's own tables, `$__timeFrom()`/`$__timeTo()`/`$__timeGroup()` macros for time-range-aware panels. The course configures the datasource and every panel by hand through Grafana's UI, with no dashboard ever checked into a repo, and points Grafana at the app's own read-write DB credentials directly.

This project's own established bar (CLAUDE.md, applied in `prepare_db`, every healthcheck, `.env`-driven secrets) is zero manual steps for `docker compose up`. The course's manual click-through setup doesn't meet that bar, so this design departs from it in two specific ways: provisioning-as-code instead of UI configuration, and a dedicated read-only DB role instead of reusing the app's credentials. Both were discussed and confirmed with the user during exploration, not unilateral departures from "how the course does it."

## Goals / Non-Goals

**Goals:**
- A reviewer running `docker compose up` on a fresh checkout sees a fully populated Grafana dashboard with zero manual configuration.
- Grafana's database access is least-privilege (read-only, scoped to the tables it needs), not the app's own credentials.
- A lightweight in-app summary exists alongside Grafana, without duplicating its charts or adding new charting gems.

**Non-Goals:**
- No live LLM-judge relevance scoring on production traffic — judges stay an offline `eval:llm`-only concept (see proposal.md's scope decision). Feedback is the live quality signal.
- No alerting, no Grafana user management beyond the single provisioned admin account, no multi-tenant dashboard variants.

## Decisions

### 1. Provisioning-as-code, not the course's manual UI setup

`grafana/provisioning/datasources/*.yml` (declares the Postgres datasource) and `grafana/provisioning/dashboards/*.yml` (a dashboard-provider config pointing at a folder of JSON dashboard files) are Grafana's own standard file-based provisioning mechanism — not something bolted on. Both are git-tracked and bind-mounted `:ro` into the container, alongside `grafana/dashboards/chat-monitoring.json` (the actual 6-panel definition, also `:ro`). Grafana's own runtime state (`grafana.db`, plugin cache) stays a completely ordinary writable named volume (`grafana_data:/var/lib/grafana`), same shape as this project's existing `postgres_data` — never committed.

`:ro` specifically: Grafana never needs to write to the provisioning or dashboard-JSON paths, and it's a concrete backstop against the `allowUiUpdates` dashboard-provisioning setting (default `false`) ever silently rewriting the repo's tracked JSON from a UI edit — enforced at the mount level rather than trusted to stay correctly configured at the Grafana settings level.

Rejected: committing the actual `grafana_data` volume/state to git. Its SQLite file embeds encrypted datasource credentials and the admin password hash (encrypted with `GF_SECURITY_SECRET_KEY`) — a real secret-leakage smell, not just untidy; it's also a binary file that would produce noisy, undiffable commits on every boot, and cross-platform/cross-version SQLite compatibility isn't something to depend on.

### 2. Dedicated read-only `grafana_reader` Postgres role, provisioned by an idempotent Rake task, not a migration and not a Postgres-side init script

The Rails app already owns all other database setup (tables, indexes, extensions) via `db:prepare`, which — since the `rework-startup-dependencies` change — runs on every boot from `rails_app/bin/docker-entrypoint`, in both `web` and `worker`. This decision extends that same ownership to the read-only role, rather than introducing a second, Postgres-side mechanism the app knows nothing about.

**Rejected: a plain ActiveRecord migration.** This was the first idea considered, and it has a real, silent failure mode worth recording precisely, since it was found by re-applying a fact this project already established empirically in `rework-startup-dependencies`: `db:prepare` on a truly fresh database takes the `DatabaseTasks#load_schema` path, which just `load`s `db/schema.rb` directly — it does not replay any migration's `up`/`change` body. `schema.rb` only contains what the schema *dumper* captures (`create_table`, `add_index`, `enable_extension`); a migration's raw `execute("CREATE ROLE ...")` call is never reflected there. Worse, `db:schema:load` also marks every migration version up to that point as "already applied" in `schema_migrations` without ever running their bodies — so on a fresh reviewer clone (the exact case this whole change is built around), a migration-based role would silently never get created, while looking fully applied. Invisible until someone tries to actually use Grafana's connection.

**Rejected: `/docker-entrypoint-initdb.d/*.sh` on the `postgres` service.** Works, and was the original design here, but only fires on a genuinely fresh, empty Postgres data directory — it can never reconcile a database that already existed before this role was introduced (this project's own current dev volume, for instance) without a separate, manual one-time step. It also splits "how does database state get established" across two unrelated mechanisms (Rails migrations for schema, a bare shell script for this one role) for no real benefit once the Rake-task option is on the table.

**Chosen: `rails_app/lib/tasks/grafana.rake`**, exposing `db:grafana_reader:ensure`, invoked unconditionally from `bin/docker-entrypoint` right after `db:prepare` — every boot, in both `web` and `worker`, using ActiveRecord's own connection (so it's the app's own DB credentials doing the provisioning, not a separate credential-holding script). Because it's not migration machinery, there's no `schema.rb`-replay gap to fall into, and because it runs every boot rather than only at first-init, it naturally reconciles a pre-existing database too — the "manual migration step for the existing dev volume" this design originally needed disappears entirely.

Two things this approach doesn't get for free that migrations would have, and how they're handled:
- **Idempotency**: Postgres has no `CREATE ROLE IF NOT EXISTS`. The task rescues the "role already exists" error (`ActiveRecord::StatementInvalid`, matched on message) around the `CREATE ROLE` statement specifically; the subsequent `GRANT` statements are naturally idempotent (re-granting an already-held privilege is a harmless no-op in Postgres) and need no special handling.
- **Concurrency**: Rails' migrator automatically wraps itself in a Postgres advisory lock; this task, not being migration machinery, does not get that for free. Since `web` and `worker` both run this on boot, a `CREATE ROLE` race on a truly fresh cluster is possible in principle. Consistent with this project's established precedent for a similarly-shaped race in `rework-startup-dependencies` (the `db:prepare` schema-load race was accepted as a rare, rescued/documented edge case rather than given real advisory locking) — the same treatment applies here, and is lower-stakes: a `CREATE ROLE` race just means one side's rescue clause fires, not a partially-created schema.

Grants: `SELECT` on `retrieval_logs`, `feedbacks`, `messages`, scoped to the primary database (the only one of this project's four Rails-managed databases these tables actually live in — `queue`/`cache`/`cable` are unrelated to Grafana's panels). Confirm at apply time whether any panel ends up needing `chats` (e.g. for conversation-level grouping); add the grant only if a panel actually requires it, not preemptively.

### 3. Two new required secrets, no exception for being "lower stakes"

`GRAFANA_ADMIN_PASSWORD` and `GRAFANA_DB_PASSWORD` both follow the exact existing `.env.example` pattern (`changeme` placeholder, `${VAR:?must be set in .env}` guard) rather than a baked-in default like `admin`/`admin`. Grafana here only exposes read-only monitoring data, so the stakes are lower than e.g. `OPENAI_API_KEY` — but default Grafana credentials left unset are a genuinely common real-world exposure pattern, and this project hasn't carved out a "this one's lower-stakes so it's fine to relax" exception anywhere else. Consistency wins.

### 4. In-app Monitoring page stays deliberately thin

4 stat cards (total queries, avg response time, total cost, feedback ratio) via plain ActiveRecord aggregate queries (`COUNT`/`AVG`/`SUM`/ratio) — no `chartkick`/`groupdate`, no time-series rendering in-app at all. This is an explicit scope reduction from PLAN.md's original chartkick-based plan (written before this Grafana-first pivot): the charting weight moves entirely to Grafana's 6 provisioned panels. Same "own controller, own nav entry, no new AR model" pattern as the existing `EvaluationsController#show`.

## Risks / Trade-offs

- **[Risk]** `GRAFANA_ADMIN_PASSWORD` is first-boot-only for Grafana itself (same as `POSTGRES_PASSWORD` already is for Postgres) — changing it in `.env` after Grafana's own volume already has initialized state doesn't retroactively rotate the admin password. Not the same limitation as `grafana_reader`'s password, which the Rake task *does* reconcile every boot (it re-runs `CREATE ROLE`/rescues "already exists," but doesn't currently `ALTER ROLE ... PASSWORD` on an existing role either — so rotating `GRAFANA_DB_PASSWORD` after the role already exists also won't take effect without an explicit `ALTER ROLE`, worth deciding at apply time whether the task should handle rotation or not). → Not a new class of problem for this project (same shape as `POSTGRES_PASSWORD`'s existing behavior); document rather than solve differently here unless rotation turns out to matter in practice.
- **[Risk]** A `CREATE ROLE` race between `web` and `worker` booting simultaneously against a truly fresh cluster. → Accepted, per the same precedent `rework-startup-dependencies` established for a similarly-shaped race — rescued via the idempotency handling in Decision 2, not solved with real advisory locking.
- **[Risk]** Exact Grafana provisioning YAML syntax for env-var substitution of the datasource password (likely `secureJsonData.password: $GRAFANA_DB_PASSWORD`, unconfirmed) needs verification against the actual pulled Grafana version, not assumed from memory. → Verify empirically at apply time before finalizing the datasource YAML.
- **[Risk]** Healthcheck tooling available inside the official `grafana/grafana` image (Alpine-based) is unconfirmed — this project's convention is "use a tool already in the image," and podman here requires `CMD-SHELL` form specifically. → Verify empirically at apply time (e.g. `podman run --rm grafana/grafana which curl wget` or similar) before writing the healthcheck; Grafana also exposes a `/api/health` HTTP endpoint as a fallback target if no shell HTTP client exists in the image.
- **[Risk]** Nested bind-mount layout — a `:ro` mount for `grafana/dashboards` needs to coexist with the writable `grafana_data` named volume covering `/var/lib/grafana` more broadly. Docker/Podman generally resolves this correctly (the more specific path wins), but this project has hit real podman-compose-specific surprises before (`--requires` graph resolution, `service_healthy` not gating start order). → Verify empirically under podman-compose specifically, not assumed safe by Docker-general knowledge alone.

## Verified after initial apply

The user reported a Grafana UI warning after the change was implemented and marked complete: "You do not currently have a default database configured for this data source" on every panel. Root cause: Grafana's postgres datasource (`grafana-postgresql-datasource`) accepts the target database via the legacy top-level `database:` field in provisioning YAML, and that field alone is sufficient for actual query execution (confirmed — `/api/ds/query` calls against the datasource succeeded, `status: 200`, throughout apply-time testing, both before and after this fix) — but the dashboard UI's own "is a database configured" check specifically looks at `jsonData.database`, which the original provisioning YAML never set. Cosmetic-but-blocking: the warning banner appeared even though queries worked underneath it.

Fixed by adding `database: rails_app_production` under `jsonData` too (alongside the existing top-level `database` field) in `grafana/provisioning/datasources/postgres.yml`. Verified live: after a `grafana` container restart to reload provisioning, `GET /api/datasources/uid/postgres_grafana_reader` shows `jsonData.database` set, and the real dev database's 4 existing `retrieval_logs` rows (spanning 2026-08-12 to 2026-08-19, all within the dashboard's default "Last 7 days" window) now return correctly from the same panel query that previously showed the warning.
