## Why

The app has no real deployment path beyond local `docker compose up` and no access control — anyone who finds it can use the chat, browse `/monitoring`, and run `/evaluation`. To make this a real, reviewable capstone deployment (a live URL a grader can visit), it needs to run on the internet behind a login, on infrastructure the user actually controls. Kamal is the deployment tool the user chose; a Debian VM with SSH access is already provisioned, sized, and DNS-pointed for it.

## What Changes

- Deploy `web` to a Debian VM via Kamal 2, behind `kamal-proxy` for automatic Let's Encrypt SSL on `llm-zoomcamp-project.alfonsoalba.com`.
- Add Thruster to the `web` image only (HTTP-only mode — `kamal-proxy` is the sole TLS terminator), wrapping Puma as the container's boot process for asset caching/compression/X-Sendfile.
- `worker` and `embedder` keep their separate, deliberately-slim images (not unified with `web`) — built and pushed via two build-only satellite Kamal configs, then run as Kamal `accessories:` alongside `postgres` and `grafana`.
- A local, Kamal-managed Docker registry runs on the VM itself — no external registry account needed.
- `bin/rails generate authentication` gates the entire app behind login (deny-by-default) for a single fixed admin user — no registration, no password reset. The admin user is seeded automatically from `ADMIN_EMAIL`/`ADMIN_PASSWORD` via the existing `db:prepare`-triggers-`db:seed`-on-fresh-database mechanism, with zero new deploy-time steps.
- **BREAKING** (for anyone currently using the app unauthenticated): every route, including chat, `/monitoring`, and `/evaluation`, now requires signing in first.
- A new, gitignored `.env.production` holds the real deployment secret values; `.kamal/secrets` sources from it. Root `.env` keeps its existing role (local dev / `docker compose` only) and gains dev-scoped `ADMIN_EMAIL`/`ADMIN_PASSWORD` values, distinct from `.env.production`'s real ones. **BREAKING** (for this project's prior convention): reverses `rails-app-scaffold`/`setup-postgres-compose`'s deliberate single-`.env`-file design — see design.md.
- `docker-compose.yml` and the local-dev workflow are untouched — this is an additive production path, not a replacement of local/reviewer usage.

## Capabilities

### New Capabilities
- `deployment`: Kamal-based production deployment — the app role, Thruster, the local registry, accessory mapping for `postgres`/`worker`/`embedder`/`grafana`, health checks, startup-ordering guarantees, and secrets sourcing.
- `authentication`: single fixed admin user, deny-by-default login gating the whole application, automatic seeding, no self-service registration or password reset.

### Modified Capabilities
(none — `rails-app`/`postgres-database` describe the docker-compose/local-dev path, which is untouched)

## Impact

- `rails_app/Gemfile` — add `kamal`, `thruster`.
- `rails_app/Dockerfile` — `web` target's `CMD` wraps Puma with `bin/thrust`; `HEALTHCHECK` moves from port 3000 to port 80 (through Thruster). `worker` target untouched.
- `rails_app/bin/thrust` — new binstub (`bundle binstubs thruster`).
- `rails_app/db/seeds.rb` — seeds the one admin `User` from `ADMIN_EMAIL`/`ADMIN_PASSWORD`.
- `rails_app/app/models/user.rb`, `session.rb`, `current.rb` — new, from the generator.
- `rails_app/app/controllers/sessions_controller.rb`, `app/controllers/concerns/authentication.rb` — new, from the generator.
- `rails_app/app/controllers/application_controller.rb` — includes `Authentication`.
- Deleted (generated but unused for a single-fixed-user setup): `PasswordsController`, `PasswordsMailer` + views, password-reset routes, the "forgot password" link, and their generated tests.
- Root `.env` / `.env.example` — add dev-scoped `ADMIN_EMAIL`, `ADMIN_PASSWORD`.
- New: `.env.production` (gitignored, real deployment secret values), `.env.production.example`.
- New: `config/deploy.yml`, `config/deploy.worker.yml`, `config/deploy.embedder.yml`, `.kamal/secrets`.
- `.gitignore` — add `.env.production` (the existing `.env` entry is an exact-filename match, doesn't cover it).
- No changes to `docker-compose.yml`, `rails_app/config/puma.rb`, or `rails_app/bin/docker-entrypoint`.
