## Context

`rails_app/config/database.yml`'s `production` block already reads `host`/`port`/`username`/`password`, the last two via a no-default `ENV["POSTGRES_USER"]`/`ENV["POSTGRES_PASSWORD"]` (correct there — it's a required secret, compose's `${VAR:?...}` already enforces it's set). `development`/`test` currently have none of these keys at all — Rails' generated defaults, which assume a Unix-socket-reachable local Postgres this project doesn't have (Postgres always runs in the `docker-compose`/`podman-compose` container).

## Goals / Non-Goals

**Goals:**
- Local `bin/rails` commands connect to the containerized Postgres with zero required shell configuration, using `.env.example`'s own placeholder values as the working default.

**Non-Goals:**
- Auto-loading `.env` into the shell for arbitrary commands (e.g. via `dotenv-rails`, `direnv`, or mise's `env_file` support) — a different, more general problem than just the Rails DB connection, out of scope here. If broader `.env`-in-shell ergonomics become a recurring pain point, that's a separate change.
- Changing `production`'s block — already correct, not touched.

## Decisions

**`username`/`password` use `ENV.fetch(key, default)` with a default matching `.env.example`, not a no-default `ENV["..."]` read like `production`.** The alternative (mirroring `production` exactly) would preserve "one consistent credential story project-wide" but doesn't solve the actual problem — it would just shrink "set `DATABASE_URL` every command" down to "set two `POSTGRES_*` vars every command," still manual. A literal default is judged acceptable specifically because `development`/`test` credentials are a throwaway local/test Postgres password, not the production secret `CLAUDE.md`'s "never assume a default for a real secret" rule protects — that rule is about compose's `${VAR:?must be set in .env}` enforcement for the actually-running service's real credentials, not a client-side convenience default that already matches a tracked, non-secret `.env.example` file.

**`port` uses `ENV.fetch("POSTGRES_PORT", 5432)`**, matching the `<SERVICE>_PORT` convention already used in `docker-compose.yml` (`${POSTGRES_PORT:-5432}`) — same default, same override variable name, so a contributor who already customized `POSTGRES_PORT` in their `.env` for `docker compose` doesn't need a second place to change it for local Rails commands to still work (Rails doesn't auto-read `.env`, so this override only takes effect if the contributor's shell happens to have `POSTGRES_PORT` exported some other way — see Non-Goals — but it's a no-cost consistency win either way).

**`host: localhost`**, not `production`'s `host: postgres` — `postgres` is a compose network alias, only resolvable from inside the compose network; a local `bin/rails` process talks to the container over its published host port instead.

## Risks / Trade-offs

- **A tracked file now contains a literal default password string (`changeme`).** → Acceptable: it's already the literal value documented in `.env.example`, a non-secret placeholder by design: anyone can already read it there. No new information is disclosed.
- **If a contributor changes their `.env`'s `POSTGRES_PASSWORD` without also exporting it to their shell before running local Rails commands, the local command will fail to authenticate** (default no longer matches the running container's real password). → Acceptable and self-evident: the error is a clear Postgres auth failure, not silent misbehavior, and only affects contributors who've deviated from the documented defaults.
