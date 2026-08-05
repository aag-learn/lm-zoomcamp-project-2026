## 1. Ruby toolchain

- [x] 1.1 Add `"ruby" = "latest"` to `mise.toml`'s `[tools]` table
- [x] 1.2 Run `mise install` and confirm `ruby`/`rails`/`bundle` resolve on `PATH`

## 2. Rails scaffold

- [x] 2.1 Run `rails new rails_app --database=postgresql --skip-docker --skip-kamal --skip-thruster` from the repo root (scaffolds into a `rails_app/` subdirectory, symmetric with `embedder/`; not `rails/` — collides with the `Rails` framework constant, verified)
- [x] 2.2 Confirm `rails_app/Gemfile` includes `gem "pg"` and Solid Queue/Cache/Cable are installed (`rails_app/config/queue.yml`, `rails_app/config/cache.yml`, `rails_app/config/cable.yml`, `rails_app/config/recurring.yml`, `rails_app/bin/jobs` all present)
- [x] 2.3 Confirm `rails_app/config/routes.rb` includes the default `/up` health check route

## 3. Database and credentials wiring

- [x] 3.1 Edit `rails_app/config/database.yml`'s `production` block: replace the Rails-generated app-specific username/password with `ENV["POSTGRES_USER"]`/`ENV["POSTGRES_PASSWORD"]`, keep the four Rails-generated database names (primary/queue/cache/cable) as-is. Also added `host: postgres` / `port: 5432` — the generated block had neither, which would default to a local Unix socket connection and never reach the `postgres` container
- [x] 3.2 Add `RAILS_MASTER_KEY` (value from the generated `rails_app/config/master.key`) to the repo-root `.env` and a placeholder to `.env.example`
- [x] 3.3 Confirm `rails_app/config/master.key` is gitignored (Rails does this by default — verify, don't assume) — confirmed via `/config/*.key` in `rails_app/.gitignore` and `jj status` showing no trace of it

## 4. Dockerfile

- [x] 4.1 Create `rails_app/Dockerfile` with a shared base stage: Ruby base image, `libpq-dev`/build tooling via `apt-get`, `bundle install`
- [x] 4.2 Add a `web` build target: sets `CMD` to run `rails server -b 0.0.0.0`
- [x] 4.3 Add a `worker` build target: installs `ansible-core` via `uv tool install` (not raw `pip` — Debian's PEP 668 externally-managed-environment restriction blocks that without extra flags; `uv tool install` sidesteps it cleanly and matches the `uv` convention already established for `embedder/`). `uv` transparently downloaded its own Python since the Ruby base image has none — no extra `apt-get install python3` needed. Sets `CMD` to run `bin/jobs`
- [x] 4.4 Verify `ansible-core` is present in the `worker` target image and absent from the `web` target image — confirmed via direct `podman run`: `worker`'s `ansible-doc -j ansible.builtin.copy` returns valid JSON, `web` has no `ansible-doc` on `PATH` at all

## 5. Compose integration

- [x] 5.1 Add a `web` service to `docker-compose.yml`: `build: {context: ./rails_app, target: web}`, `environment` for `RAILS_ENV=production`, `POSTGRES_*`, `RAILS_MASTER_KEY`; `depends_on` `postgres` and `embedder` (both `condition: service_healthy`); healthcheck against `/up`. Published `${WEB_PORT:-3000}:3000` (new env var, matching the `POSTGRES_PORT`/`EMBEDDER_PORT` convention, added to `.env`/`.env.example`). Healthcheck uses `ruby -rnet/http` (not `curl`/`python`, neither present in this pure-Ruby image) — same "use what the image already has" approach as `embedder`'s Python-only healthcheck
- [x] 5.2 Add a `worker` service to `docker-compose.yml`: same build context (`./rails_app`) with `target: worker`, same environment/`depends_on`, no healthcheck (per design decision 4), `CMD` runs `bin/jobs`
- [x] 5.3 Confirm `docker compose up -d --build web worker` boots both containers without immediate crash-looping — `web` reached `healthy`; `worker` exited with the expected `ActiveRecord::NoDatabaseError: Database not found: rails_app_production_queue`, not an unrelated crash (databases don't exist until `db:prepare` runs, §6)

## 6. Verification

- [x] 6.1 Confirm `web` reaches `healthy` via its `/up`-based healthcheck
- [x] 6.2 Run `docker compose exec web bin/rails db:prepare` once; confirm it creates and migrates all four databases (primary/queue/cache/cable) without error — all four created cleanly (a harmless "libvips not installed" warning appears, unrelated to Active Storage image-variant processing we don't use — not an error)
- [x] 6.3 Restart `worker` after `db:prepare` and confirm its logs show Solid Queue polling successfully, not crash-looping on a missing schema — Supervisor, Dispatcher, Worker, and Scheduler all started, container stayed running (not exited)
- [x] 6.4 Run `docker compose exec worker ansible-doc -j ansible.builtin.copy` and confirm it returns valid JSON
- [x] 6.5 Confirm `docker compose exec web ansible-doc -j ansible.builtin.copy` fails (command not found) — `ansible-core` must not have leaked into the `web` image
- [x] 6.6 Run `git status` (or equivalent) and confirm `rails_app/config/master.key` and `.env` do not appear as trackable/untracked

## 7. README

- [x] 7.1 Extend the README's existing Development section to cover the Ruby/Rails setup step (found missing from this file during implementation — `proposal.md` and `design.md` both call for it, but it was accidentally dropped when `tasks.md` was written)

## 8. Automatic database preparation

- [x] 8.1 Add a `prepare_db` service to `docker-compose.yml` (named `migrate` initially, renamed after implementation — see 8.7): reuses `build: {context: ./rails_app, target: web}`, `command: ["bin/rails", "db:prepare"]`, `restart: "no"`, same `environment` as `web`/`worker`, `depends_on: postgres: condition: service_healthy`
- [x] 8.2 Add `depends_on: prepare_db: condition: service_completed_successfully` to both `web` and `worker`
- [x] 8.3 Update the README's Development section: remove the manual `docker compose exec web bin/rails db:prepare` instruction, replace with "just run `docker compose up`"
- [x] 8.4 Verify the `prepare_db` service's command succeeds standalone against a fresh (never-prepared) set of databases — dropped all four Rails databases, ran the service alone, confirmed it exited `0` and recreated all four from scratch
- [x] 8.5 Verify `web`/`worker` start successfully when brought up *after* `prepare_db` has already completed (manually sequenced, since `podman-compose -d`'s `service_completed_successfully` support could not be verified end-to-end — see design.md decision 9). `web` came up healthy via `podman-compose up -d web worker`; `worker` hit an unrelated, persistent Podman-level bug in this sandbox (`--requires` dependency-graph resolution failing on a freshly-recreated `postgres` container — reproducible, not a timing fluke, and unrelated to the compose config's correctness) — worked around by starting `worker` directly via `podman run` with the same image/env/network. Confirmed: Solid Queue's Supervisor/Dispatcher/Worker/Scheduler all started successfully with zero manual `db:prepare` step anywhere in the run
- [x] 8.6 Note in `tasks.md` (here) that full automatic-ordering verification under real `docker compose` is still outstanding, to flag for the user — **outstanding**: this project has only ever been tested with `podman-compose` in this sandbox. `service_completed_successfully` is correct per the Compose spec and real Docker Compose implements it properly, but that exact ordering guarantee (not just "the pieces work when sequenced manually") has not been observed end-to-end here. Worth a first real `docker compose up` smoke test — from either of you, or the first peer reviewer — to close this out.
- [x] 8.7 Rename the service from `migrate` to `prepare_db` (caught by the user after initial implementation): `migrate` undersells that the command also creates the databases from nothing on first run, not just applies schema changes — `prepare_db` matches what `bin/rails db:prepare` actually does. Renamed in `docker-compose.yml` and `README.md`
