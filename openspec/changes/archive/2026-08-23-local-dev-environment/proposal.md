## Why

Every iteration so far has gone through a full Docker/podman-compose rebuild — there is no way to run `web`/`worker`/`embedder` as local processes today. `bin/dev` exists (Rails' own scaffold) but `Procfile.dev` only runs `web`+`css`, `ansible-core` isn't installable outside the `worker` image, and `.env` is never loaded on the host. This is pure iteration-speed debt, not a rubric gap, but it's the last item before the README/reproducibility pass, and PLAN.md already commits to the target shape ("two environments, not three: development and production") — this change builds it.

## What Changes

- `mise.toml` gains `"ansible-core" = "latest"` in `[tools]` — verified directly that mise's registry entry for this shells out to `uv tool install ansible-core` itself, mechanistically identical to what `rails_app/Dockerfile`'s `worker` stage already does.
- `mise.toml` gains `apt:build-essential`, `apt:libpq-dev` (Linux) and `brew:libpq` (macOS) in `[bootstrap.packages]`, mirroring `rails_app/Dockerfile`'s `base` stage, so the `pg` gem's native extension can compile on a fresh host. `build-essential` has no Homebrew equivalent (Xcode Command Line Tools instead) — documented as a manual macOS prerequisite, not silently assumed covered.
- `mise.toml` gains two tasks: `db:prepare` (local equivalent of the container-only `bin/docker-entrypoint` schema-prep step) and `ingest` (local equivalent of the already-documented `docker compose exec worker bin/rails runner 'IngestAnsibleModulesJob.perform_now'` command).
- `rails_app/Procfile.dev` gains a `worker: bin/jobs` line.
- `rails_app/Gemfile` gains `dotenv-rails` (`development`/`test` group only), reconfigured in `config/application.rb` to read the repo-root `.env` instead of its default `rails_app/.env`, so `OPENAI_API_KEY` (and other required vars) are present for `bin/dev`, `rails console`, `rails runner`, and tests alike — currently `.env` is only loaded inside containers.
- `.env.example` gains `EMBEDDER_URL=http://localhost:8000`, used only by locally-run `web`/`worker` processes to reach a locally-run `embedder` — confirmed this variable is not read by `docker-compose.yml`, so it has no effect on the containerized path.
- `README.md`'s Development section documents the new local-process workflow as a second path alongside the existing `docker compose up -d --build` flow.
- **Discovered during verification, fixed in this change**: `rails_app/config/database.yml`'s `development`/`test` blocks never declared the `primary`/`cache`/`queue`/`cable` split `production` already has, and `config/environments/development.rb` never set `queue_adapter = :solid_queue`/`solid_queue.connects_to` the way `production.rb` does — meaning a locally-run `worker` process could never have worked at all before this change, in any prior state of the repo. Both are now added, mirroring `production`'s existing pattern.
- **Also discovered during verification, fixed in this change**: `dotenv-rails` was originally scoped to `group :development, :test`, which broke 14 existing tests once this change's own `EMBEDDER_URL` var landed in `.env` (tests picked up the real value instead of the code default their `WebMock` stubs expect). Rescoped to `group :development` only — `test` stays hermetic and never loads `.env` — with a dummy `OPENAI_API_KEY` stand-in added to `config/environments/test.rb` so `bin/rails test` still needs zero local setup.
- **Discovered live-testing the app through `bin/dev`, fixed in this change**: `config/cable.yml`'s `development` block used Action Cable's `async` adapter, which only pub/sub-broadcasts within a single process — silently breaking live Turbo Streams updates now that `worker` is a genuinely separate local process from `web` (a chat reply would save correctly but never appear without a manual page refresh). Switched `development` to `solid_cable`, matching `production` and reusing the `cable` database connection this change already added to `database.yml`.
- **User-requested addition**: Grafana's datasource was hardcoded to the `production` database, so local `bin/dev` chat traffic was invisible in Monitoring. Added a second Grafana datasource pointing at `development` (same Postgres container/role, different database) plus a datasource-picker variable on the Chat Monitoring dashboard, so local dev traffic is visible without a second dashboard to maintain.

## Capabilities

### New Capabilities

(none — this extends the existing local-tooling capability)

### Modified Capabilities

- `dev-toolchain`: adds `ansible-core` to the mise-managed tools requirement, adds `build-essential`/`libpq-dev`/`libpq` to the bootstrap-packages requirement (including the macOS asymmetry), adds a requirement for the two new mise tasks, adds a requirement for the local process-based `web`/`worker` dev workflow (`Procfile.dev`/`dotenv-rails`), and extends the README requirement to document the full local dev flow instead of just the provisioning command.
- `monitoring`: adds a requirement for a local-dev-scoped Grafana datasource + dashboard variable, so local `bin/dev` chat traffic is visible in the same Chat Monitoring dashboard as production traffic.

## Impact

- Files: `mise.toml`, `rails_app/Procfile.dev`, `rails_app/Gemfile`, `rails_app/config/application.rb`, `rails_app/config/database.yml`, `rails_app/config/environments/development.rb`, `rails_app/config/environments/test.rb`, `rails_app/config/cable.yml`, `.env.example`, `README.md`, `grafana/provisioning/datasources/postgres.yml`, `grafana/dashboards/chat-monitoring.json`.
- No application code, schema, or container-path behavior changes — `docker-compose.yml` and all Dockerfiles are untouched. Purely additive local-dev tooling; the existing `docker compose up -d --build` path keeps working exactly as before.
- New host-level dependency: `ansible-core` (via mise/uv) and a C toolchain + `libpq` headers, needed only for contributors who want to run `web`/`worker` as local processes rather than exclusively through Docker.
