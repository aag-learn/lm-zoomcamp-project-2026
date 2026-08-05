# LLM Zoomcamp Capstone: Ansible Module-Reference RAG Assistant

## Development

This project uses [mise](https://mise.jdx.dev/) to manage all local development tools and system packages. Install `mise` itself first, following the official instructions: https://mise.jdx.dev/installing-mise.html

Before running anything else, create a `mise.local.toml` file at the repo root (gitignored — it's personal to your machine, not committed) restricting `mise` to your platform's package manager:

**Linux:**

```toml
[settings]
system_packages.managers = ["apt"]
```

**macOS:**

```toml
[settings]
system_packages.managers = ["brew"]
```

This step is required, not optional. Without it, `mise` will attempt to install *every* declared package manager's packages, including trying to bootstrap Homebrew on Linux (or vice versa) to satisfy entries meant for the other platform.

**macOS only:** install Xcode Command Line Tools before bootstrapping (`xcode-select --install`). This project's `pg` gem needs a C compiler to build its native extension, and Homebrew has no `build-essential`-equivalent formula for that — `mise bootstrap` covers `libpq` (Postgres client headers) via `brew`, but not the compiler toolchain itself.

Once `mise.local.toml` is in place, provision every tool and package this project needs with one command:

```sh
mise bootstrap
```

This provisions `ruby` (and everything else declared in `mise.toml`) automatically — no separate Ruby install step needed.

### Running the app

Copy `.env.example` to `.env` and fill in real values — in particular, `RAILS_MASTER_KEY` must match `rails_app/config/master.key` (generated once by `rails new`, gitignored, never committed).

Bring up the full stack:

```sh
docker compose up -d --build
```

The `web` and `worker` services share one Rails codebase (`rails_app/`), built from the same `Dockerfile` via two different build targets — `worker` additionally has `ansible-core` installed, `web` does not. A `prepare_db` service prepares the application's databases automatically before `web`/`worker` start — nothing further to run by hand.

### Populating the knowledge base (ingestion)

`worker` runs `IngestAnsibleModulesJob` automatically on a recurring weekly schedule (Solid Queue, `rails_app/config/recurring.yml`) — it fetches every `ansible.builtin` module's documentation via `ansible-doc`, splits it into retrievable chunks (one per parameter, named example, and return value, plus one module overview), embeds each chunk via the `embedder` sidecar, and stores the result in Postgres. Each run fully replaces the previous data set atomically, so the app is never left with an empty or half-populated knowledge base.

To populate the database immediately instead of waiting for the first scheduled run, trigger it manually once:

```sh
docker compose exec worker bin/rails runner 'IngestAnsibleModulesJob.perform_now'
```

A full run takes well under a minute and produces 71 modules and roughly 1,500 chunks.

### Running locally without Docker rebuilds

The `docker compose up -d --build` flow above is this project's production-equivalent path — full container rebuilds on every code change. For faster iteration, `web`/`worker`/`embedder` can instead run as local processes, provisioned by `mise`/`uv` (see above), while Postgres and Grafana stay in `docker compose` (infra you don't want to install locally, not code you're iterating on):

```sh
# 1. Infra only
docker compose up -d postgres grafana

# 2. Prepare the local database (schema + Grafana reader role) — one-time,
#    or again after a schema change
mise run db:prepare

# 3. Start the embedder sidecar locally (separate terminal). First run
#    re-downloads model weights from Hugging Face Hub — the Docker image
#    bakes them in at build time, a plain local `uv sync` doesn't.
cd embedder && uv run uvicorn main:app --reload --port 8000

# 4. Populate the local knowledge base — requires the embedder from step 3
#    already running
mise run ingest

# 5. Start web + css + worker together (separate terminal)
cd rails_app && bin/dev
```

Copy `.env.example` to `.env` at the repo root the same way as the Docker path above — `bin/dev`, `rails console`, `rails runner`, and tests all load it automatically in development/test via the `dotenv-rails` gem (production/Docker gets its real env vars injected directly by `docker-compose.yml`, not from this file). `EMBEDDER_URL` in `.env.example` defaults to `http://localhost:8000`, matching step 3 above — it's only read by locally-run `web`/`worker` processes and has no effect on the containerized path.
