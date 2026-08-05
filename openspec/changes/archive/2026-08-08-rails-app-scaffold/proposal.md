## Why

No Rails application exists yet in this repo — no `Gemfile`, no `rails new` has run, and `ruby` isn't even declared in `mise.toml`. Every subsequent piece of the RAG pipeline described in `PLAN.md` (ingestion, retrieval, chat UI, evaluation) is Ruby code that has to live inside a booted Rails app, and the `web`/`worker` split (documented in `PLAN.md`'s architecture revision — one codebase, two Dockerfiles, `worker` alone carries `ansible-core`) needs to exist and be verified before any ingestion-specific code is written on top of it. Scaffolding this now, as its own narrow change, mirrors how `dev-toolchain-bootstrap` preceded `embedder-sidecar`: a small, independently-verifiable foundation before the feature that depends on it.

## What Changes

- Add `ruby` to `mise.toml`'s `[tools]` table.
- Run `rails new rails_app --database=postgresql` to scaffold the app inside a `rails_app/` subdirectory (single codebase, single `Gemfile`, single `app/` tree) — symmetric with `embedder/` already being its own subdirectory, keeping the repo root a clean list of components rather than Rails' many generated top-level directories mixing in with the rest of the project. (Named `rails_app/`, not `rails/` — the latter collides with the `Rails` framework constant itself and `rails new` has no way to decouple the app's module name from its directory name; verified directly.)
- Add `rails_app/Dockerfile` (a single multi-stage Dockerfile with `web` and `worker` build targets — one shared Ruby/bundler base, `worker` alone additionally installs `ansible-core`) per the architecture already decided in `PLAN.md`, adapted to a single file with build targets rather than two separate files (see `design.md`).
- Add `web` and `worker` services to `docker-compose.yml`, both building from `./rails_app` (matching `embedder`'s `./embedder` build context), `web` running `rails server` and `worker` running `bin/jobs` (Solid Queue — DB-backed, no separate broker needed), both `depends_on` `postgres` and `embedder` healthchecks.
- Smoke-test `ansible-doc -j <module>` runs successfully inside the `worker` container (proves the `ansible-core` install works, independent of any Ruby code calling it later).
- Add a one-shot `prepare_db` service to `docker-compose.yml` (reusing the `web` build target with `command: bin/rails db:prepare`) that `web`/`worker` both wait on via `depends_on: condition: service_completed_successfully` — so the databases are prepared automatically on first `docker compose up`, no manual step required. Added specifically because this project's reviewers are expected not to be developers (per `PLAN.md`'s rubric context); a manual `bin/rails db:prepare` step is exactly the kind of thing that shouldn't be required of them.
- Extend the README's existing Development section to cover the Ruby/Rails setup step.
- **Explicitly out of scope**: no migrations, no models, no `AnsibleDocClient`/`Ingestion::Chunker`/`IngestAnsibleModulesJob`, no `pgvector`/`neighbor` gems yet. This change only needs the app to boot and both containers to run — the actual ingestion pipeline is a follow-up change built on top of this one.

## Capabilities

### New Capabilities
- `rails-app`: A booted Rails application, in a single codebase, deployable as two distinct container images (`web`, pure Ruby; `worker`, Ruby + `ansible-core`) that both build from the same repo.

### Modified Capabilities
(none — `postgres-database`, `dev-toolchain`, `embedding-service` are unaffected)

## Impact

- **Affected files**: new `rails_app/` directory containing `Gemfile`/`Gemfile.lock`, full Rails app skeleton (`app/`, `config/`, `bin/`, etc.), and `rails_app/Dockerfile`; `docker-compose.yml` gains `web`/`worker`/`prepare_db` services; `mise.toml` gains `ruby`; `README.md`'s Development section extended.
- **Dependencies**: Ruby (via `mise`), Rails, `pg` gem (Postgres adapter), Solid Queue (Rails 8 default), `ansible-core` (Python, `worker` image only — same package already used by the (currently unbuilt) ingestion design, no new decision here).
- **Systems**: depends on `postgres` (already running, from `setup-postgres-compose`) and `embedder` (already running, from `embedder-sidecar`) for their respective healthchecks. No code yet depends on this app being up — it's a foundation for the next change (ingestion pipeline), not a user-facing milestone by itself.
