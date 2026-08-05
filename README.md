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
