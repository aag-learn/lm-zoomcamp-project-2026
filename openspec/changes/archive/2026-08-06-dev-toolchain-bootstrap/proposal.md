## Why

The embedder change (`embedder-sidecar`) needs `uv`, `python`, `curl`, and `jq` on a contributor's machine before any of its tasks (scaffolding the FastAPI app, running `embedder/test.sh`) can proceed, and nothing in the repo currently declares or documents how to get them. `mise.toml` only lists `claude` and the `openspec` CLI so far. The user develops this project across both a Mac and a Linux box, so the package-manager story needs to work on both. Declaring these as `mise`-managed tools/packages now — rather than assuming they're already installed — keeps the project's Reproducibility story intact from the start: a contributor only needs `mise` itself, not a manually-assembled toolchain, and a `README.md` gives them the one command to run.

## What Changes

- Add `uv` and `python` to `mise.toml`'s `[tools]` table (`"uv" = "latest"`, `"python" = "latest"`), so `mise install` (or `mise bootstrap`) provisions both.
- Add `curl` and `jq` to `mise.toml`'s `[bootstrap.packages]` table via **both** the `apt:` and `brew:` managers (`"apt:curl"`, `"apt:jq"`, `"brew:curl"`, `"brew:jq"`, all `"latest"`), so `mise bootstrap` installs them as system packages on either the Linux box (apt) or the Mac (brew).
- Add a gitignored `mise.local.toml` convention: each contributor sets `[settings] system_packages.managers = ["apt"]` (Linux) or `["brew"]` (macOS) in their own local, uncommitted `mise.local.toml`. This is required, not optional — verified directly against the installed `mise` binary that, without it, `brew:` entries are **not** skipped on Linux; `mise` instead tries to bootstrap Homebrew (Linuxbrew) via `sudo` to satisfy them, which is unwanted here since `apt` already covers Linux.
- Add `mise.local.toml` to `.gitignore`.
- Create `README.md` at the repo root with a single **Development** section: assumes `mise` is already installed, links to the official mise installation page, documents creating a per-machine `mise.local.toml`, and gives the command (`mise bootstrap`) that provisions every tool/package the project needs.

## Capabilities

### New Capabilities
- `dev-toolchain`: Declares and documents the project's local development tool/package dependencies (via `mise`), so a contributor can go from a fresh clone to a fully-provisioned toolchain with one documented command.

### Modified Capabilities
(none — `postgres-database` and `embedding-service` are unaffected by this change)

## Impact

- **Affected files**: `mise.toml` (add `uv`, `python` to `[tools]`; add `apt:curl`, `apt:jq`, `brew:curl`, `brew:jq` to `[bootstrap.packages]`); `.gitignore` (add `mise.local.toml`); new `README.md`.
- **Dependencies**: none new at the application level — this only affects what's available on a contributor's machine, not what the running services depend on.
- **Systems**: purely a local dev-environment/documentation change. No effect on `docker-compose.yml` or any containerized service (containers get their own dependencies via their Dockerfiles, independent of the host's `mise`-managed tools).
