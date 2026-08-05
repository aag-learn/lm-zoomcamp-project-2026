# CLAUDE.md

Guidance for Claude Code sessions working in this repo. `PLAN.md` is the original planning doc (capstone architecture rationale) — read it for *why* the project exists and its overall shape, but treat `openspec/specs/` as the current source of truth, since several PLAN.md decisions have since been revised (see `openspec/changes/archive/`).

## Workflow: everything goes through OpenSpec

This project uses OpenSpec (`/opsx:*` commands) for every infra/feature change: explore → propose (proposal/design/specs/tasks) → apply → archive. Don't hand-edit `docker-compose.yml`, add services, or scaffold new components without a change behind it — that's how the reasoning for *why* something is built a certain way stays discoverable later. `openspec/specs/` holds the current, consolidated capability specs; `openspec/changes/archive/` holds the historical proposal/design/tasks for each change, including reasoning for decisions that later got reversed or revised mid-implementation.

## Architecture (see PLAN.md and openspec/specs/ for full detail)

- One Rails codebase (`rails_app/`) builds into two container images — `web` (pure Ruby) and `worker` (Ruby + `ansible-core`) — via **one multi-stage `rails_app/Dockerfile`** with `web`/`worker` build targets, not two separate Dockerfiles. Avoids duplicating the Ruby/bundler setup across files that would drift out of sync.
- `ansible-core`/`ansible-doc` lives in `worker`, not the Python sidecar — domain cohesion (ingestion owns its own data fetching) won out over language-purity. This reverses an earlier version of the plan; see the `PLAN.md` architecture-revision section and `openspec/changes/archive/2026-08-08-embedder-sidecar/`.
- `embedder/` is a Python FastAPI sidecar, **ML-serving only** (`/embed`, `/rerank`) — no CLI/subprocess responsibilities, no `ansible-core`.
- Each component gets its own subdirectory (`rails_app/`, `embedder/`) — repo root stays a short list of components, not Rails' generated tree mixed in with everything else. **Never name a Rails app directory `rails/`** — collides with the `Rails` framework constant; use `rails_app/` (verified: `rails new rails` fails outright, no flag decouples app name from directory name).
- `prepare_db` compose service (not `migrate` — name reflects `db:prepare`, which also creates databases from nothing on first run, not just applies schema changes) runs once before `web`/`worker` start, via `depends_on: condition: service_completed_successfully`. This project's reviewers are expected *not* to be developers — no step should require manually running a Rails command.
- Rails' default Rails 8 multi-database topology (primary/queue/cache/cable) is kept as-is, not consolidated — confirmed with the user, not assumed.

## Secrets and configuration

- All secrets live in root `.env` (gitignored), documented with placeholders in `.env.example`. Never assume a default for a real secret — compose files use `${VAR:?must be set in .env}` for required values.
- Host port mappings follow a `<SERVICE>_PORT` convention with sane defaults: `POSTGRES_PORT` (5432), `EMBEDDER_PORT` (8001), `WEB_PORT` (3000).
- `rails_app/config/database.yml`'s production block reads `ENV["POSTGRES_USER"]`/`ENV["POSTGRES_PASSWORD"]` directly (edited away from Rails' generated app-specific var name) — one consistent credential story project-wide, not two parallel naming schemes for the same secret.
- Every service healthcheck uses a tool already present in its own image — never add `curl`/`python` just for a healthcheck. `embedder` uses Python's `urllib`, `web` uses Ruby's `net/http`, `postgres` uses `pg_isready`.

## Tooling (mise)

- `mise` manages all local dev tools (`mise.toml` `[tools]`) and system packages (`[bootstrap.packages]`, `apt:`/`brew:` prefixes). Run `mise bootstrap` to provision everything.
- Each machine needs its own gitignored `mise.local.toml` setting `[settings] system_packages.managers = ["apt"]` (Linux) or `["brew"]` (macOS). **This is required, not optional** — verified directly: without it, declaring both `apt:` and `brew:` packages makes `mise` on Linux actually attempt to bootstrap Homebrew (via `sudo`) to satisfy the `brew:` entries, instead of skipping them. `mise.linux.toml`/`mise.macos.toml` auto-composition (what the docs suggest) does **not** work in the installed mise version — confirmed by testing, not by trusting the docs.
- `uv tool install <pkg>` for one-off CLI tools in a Dockerfile (e.g. `ansible-core` in `worker`) — sidesteps Debian's PEP 668 externally-managed-environment restriction that blocks plain `pip install`, and downloads its own Python if the base image has none.
- CPU-only `torch`: plain `torch`/`sentence-transformers` pulls the full CUDA/`nvidia-*` wheel stack by default. Pin via `[[tool.uv.index]]` (`pytorch-cpu`, `explicit = true`) + `[tool.uv.sources]` — but `torch` must be listed as a **direct** dependency for the override to take effect; it's silently ignored if only pulled in transitively.

## This sandbox's podman quirks (not real bugs in the project)

This environment uses `podman`/`podman-compose`, not real Docker. Known gaps, confirmed by direct testing — don't assume they indicate a problem with the actual `docker-compose.yml`:
- Short image names (`ruby:4.0-slim`, `pgvector/pgvector:pg18`) need `podman pull docker.io/...` + `podman tag` first, or they fail to resolve.
- `podman-compose`'s exec-array healthcheck form (`test: ["CMD", ...]`) has a quoting bug that produces a shell syntax error — use `CMD-SHELL` (a single string) instead. Every healthcheck in `docker-compose.yml` uses `CMD-SHELL` for this reason.
- `podman-compose up -d`'s `depends_on: condition: service_completed_successfully` does **not** actually wait for exit — it only guarantees start order via Podman's `--requires`, confirmed via a minimal reproduction. Real Docker Compose implements this correctly. This means `prepare_db`'s ordering guarantee has only been verified by manual sequencing here, not end-to-end under real `docker compose` — worth a real smoke test when available.
- Occasional `--requires` dependency-graph resolution failure when a dependency container was just recreated (`"container X depends on container Y not found in input list"` despite Y running fine) — a Podman-level bug in this sandbox; work around with a direct `podman run` using the same image/env/network, don't chase it as an app bug.

## Jujutsu (jj) workflow

- Repo is colocated jj + git.
- **`PLAN.md` is intentionally never committed** unless explicitly asked — it's kept as local/uncommitted working context.
- To commit everything currently uncommitted *except* certain files (typically `PLAN.md`), use `jj split -m "<message>" <files-to-include...>` rather than `git add`/`git commit` — lists the paths to include in the new commit; everything else stays in the working-copy revision.
- Commit messages: short, lead with *why*, not a changelog of *what*.
- Watch for accidentally-nested git repos when scaffolding new subprojects — `rails new` runs its own `git init` unless `--skip-git` is passed, which silently hides the entire generated directory from the outer repo's tracking until caught (`ls -la <dir>/.git`).

## Working style established in this project

- Verify empirically before writing something into a design doc or Dockerfile — check actual tool output, resolve real image tags, run a scratch test — rather than assume. This repo's change history has several corrections from doing this (Postgres pg16→pg18, Python 3.12→3.14, CPU-vs-CUDA torch, `migrate`→`prepare_db`, the nested-git-repo catch).
- When implementation reveals a design gap or a wrong earlier assumption, pause and update `proposal.md`/`design.md`/`tasks.md` before continuing — don't just patch code silently. Reversed Non-Goals get called out explicitly, not quietly dropped.
- Ask before deciding on genuinely open tradeoffs with real consequences (e.g. Python version, CPU vs GPU torch, single vs multi-database, directory naming) — don't unilaterally pick when the user would reasonably want a say.
