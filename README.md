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
