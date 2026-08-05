## Context

This is the first infrastructure piece of the Ansible RAG capstone (see `PLAN.md`). No Rails app, migrations, or other services exist yet. Later changes will add a `web` service (Rails), a `worker` service (Solid Queue), and an `embedder` service (Python sidecar) to the same `docker-compose.yml` — this change only needs to make sure the `postgres` service and the compose file's env-var conventions are solid enough for those later services to build on without rework.

Two capabilities must coexist in the same table later (`chunks`): vector similarity search and full-text search. Vector search needs the `pgvector` extension, which is **not** part of stock Postgres images and requires a purpose-built image or a custom Dockerfile. Full-text search (`tsvector`/GIN) is a built-in Postgres feature — it needs no special image, just documenting that it "just works" on top of whatever image also has pgvector.

## Goals / Non-Goals

**Goals:**
- A single `docker-compose.yml` service (`postgres`) that boots a `pgvector`-capable Postgres, ready for `CREATE EXTENSION vector;` in a future Rails migration.
- All credentials and connection parameters sourced from environment variables, populated from a `.env` file that is never committed.
- Data persists across `down`/`up` cycles via a named volume.
- A healthcheck so later services (`web`, `worker`) can declare `depends_on: postgres: condition: service_healthy`.

**Non-Goals:**
- No Rails app, migrations, `neighbor`/`pgvector` gem wiring, or schema (that's the next change, once `rails new` happens).
- No production hardening (TLS, connection pooling, backup/restore strategy, replica setup) — this is a local/dev-oriented compose setup, consistent with the project's Reproducibility goal (`docker compose up` should just work for a grader).
- No seed data or extension-creation SQL baked into this change — the plan explicitly keeps `CREATE EXTENSION vector;` inside the Rails migration, not compose-time init scripts, so ownership of schema stays in one place (Rails).

## Decisions

**1. Image: `pgvector/pgvector:pg18`** (official pgvector project image, built on top of the official Postgres image)
- Alternative considered: stock `postgres:18` + a custom `Dockerfile` running `apt-get install postgresql-18-pgvector`. Rejected — adds a Dockerfile and build step for something the pgvector project already publishes and maintains as a drop-in image; no benefit here.
- Alternative considered: `ankane/pgvector`. Rejected in favor of the pgvector-org-maintained image now that `pgvector/pgvector` exists — same maintainer as the extension itself, less risk of drift.
- Alternative considered: `pg16`/`pg17` (older, more field-tested majors). Rejected — no Rails app or gem (`pg`, `neighbor`) exists yet to impose a compatibility ceiling, so there's no reason to hold back from the current major; `pg18` is officially published and supported by the `pgvector/pgvector` image (confirmed via Docker Hub tags, pgvector 0.8.6). `pg18` chosen as the current Postgres major version; later changes (Rails app) should match this major version.

**2. Env vars via `.env` + compose's built-in auto-loading**
- Docker Compose automatically reads a `.env` file in the same directory as `docker-compose.yml` and makes its values available for `${VAR}` interpolation inside the compose file — no explicit `env_file:` directive needed for this substitution.
- The `postgres` service's `environment:` block references `${POSTGRES_USER}`, `${POSTGRES_PASSWORD}`, `${POSTGRES_DB}` directly, so the official Postgres image's own entrypoint script picks them up for first-run initialization.
- `POSTGRES_PASSWORD` has **no default** in the compose file (an unset/empty value should fail loudly rather than silently boot an unauthenticated or blank-password instance) — `.env.example` documents that it's required.
- `POSTGRES_PORT` (host-side port mapping) *does* get a fallback (`${POSTGRES_PORT:-5432}`) since it's not a secret and a sensible default avoids friction for the common case.

**3. Named volume for persistence, mounted at `/var/lib/postgresql` (not `/var/lib/postgresql/data`)**
- `postgres_data:/var/lib/postgresql`, declared under top-level `volumes:`. Keeps data across `docker compose down` (without `-v`), consistent with normal dev workflow; `docker compose down -v` remains the escape hatch for a clean-slate reinit.
- **Discovered during implementation**: starting with the Postgres 18 official image, mounting a volume directly at the old `/var/lib/postgresql/data` path causes the container to refuse to start (`Exited (1)`), because the pg18+ images switched to `pg_ctlcluster`-style, version-namespaced data directories to support in-place `pg_upgrade --link` across majors later. The image's entrypoint explicitly detects the legacy mount point and errors out rather than silently doing the wrong thing. The fix is to mount the volume one level up, at `/var/lib/postgresql`, letting the image manage its own versioned subdirectory underneath. Verified end-to-end with `podman-compose` in this environment: container reached `healthy`, and data survived a `down`/`up` cycle. This is exactly the kind of newest-major rough edge flagged as a risk when pg18 was chosen over pg16/pg17.

**4. Healthcheck via `pg_isready`**
- Standard `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}` on an interval short enough that dependent services (added in later changes) don't wait long after a fresh `up`.

## Risks / Trade-offs

- **[Risk] `.env` accidentally committed** → Mitigation: `.gitignore` entry for `.env` added in this same change; only `.env.example` (placeholder values) is tracked.
- **[Risk] Host port `5432` conflicts with a locally-installed Postgres** → Mitigation: `POSTGRES_PORT` env var with a `.env.example`-documented override; default stays `5432` for the common case.
- **[Risk] Volume initialized before `pgvector` was part of the image** (e.g. someone previously ran plain `postgres:16` against the same volume path) → Postgres only runs its `initdb`/extension-availability setup on an empty data directory; a stale volume would need `docker compose down -v` and a fresh `up`. Documented as a troubleshooting note rather than solved architecturally, since it only affects a rare local-history edge case.
- **[Risk] Newest Postgres major (`pg18`) has less field mileage than `pg16`/`pg17`, and the Rails `pg` gem or `neighbor` gem could lag in full support** → Mitigation: pin the exact tag once chosen; if a later Rails-app change hits a gem incompatibility, downgrading the image tag here is a one-line change with no schema migration involved yet.
- **[Trade-off] No init-time `CREATE EXTENSION`** → keeps this change's scope purely "make the extension available," while schema ownership (when to actually create it) stays entirely in Rails migrations, avoiding two sources of truth for schema state. Slight downside: the extension's *availability* can't be verified until the first migration runs in a later change.

## Migration Plan

- Purely additive: new files (`docker-compose.yml`, `.env.example`, `.gitignore` update). Nothing to migrate away from.
- Rollout: `cp .env.example .env`, fill in real values, `docker compose up -d postgres`, verify healthy via `docker compose ps`.
- Rollback: `docker compose down` (add `-v` only if the volume itself needs to be discarded) and remove the added files.

## Open Questions

- None blocking — Postgres major version (`pg18`) and image choice are treated as settled for this change; revisit only if a later Rails-app change surfaces a compatibility issue with the `pg` gem or `neighbor` gem (e.g. if either lags behind Postgres 18 support at that point).
