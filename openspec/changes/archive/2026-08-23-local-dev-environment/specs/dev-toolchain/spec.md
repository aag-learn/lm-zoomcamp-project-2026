## MODIFIED Requirements

### Requirement: Project-managed tools declared in mise
The system SHALL declare `uv`, `python`, and `ansible-core` in `mise.toml`'s `[tools]` table, so `mise install`/`mise bootstrap` provisions all three without any manual installation step.

#### Scenario: Tools install via mise
- **WHEN** a contributor with `mise` installed runs `mise install` (or `mise bootstrap`) from the repo root
- **THEN** `uv`, `python`, and `ansible-core` are all installed and available on `PATH` within the `mise`-managed environment

#### Scenario: ansible-core provides ansible-doc for local worker processes
- **WHEN** `ansible-core` is installed via `mise`
- **THEN** the `ansible-doc` executable is available on `PATH`, so a locally-run `worker` process (see the local process-based dev workflow requirement) can shell out to it exactly as the containerized `worker` image does

### Requirement: System packages declared as mise bootstrap packages for both apt and brew
The system SHALL declare `curl`, `jq`, and `libpq-dev` in `mise.toml`'s `[bootstrap.packages]` table via both the `apt:` and `brew:` managers (as `libpq` on `brew`), so `mise bootstrap` can install all of them as system packages on either a Debian/Ubuntu-based Linux machine or a Mac. The system SHALL additionally declare `build-essential` via the `apt:` manager only, since Homebrew has no equivalent formula — the macOS equivalent (Xcode Command Line Tools) is a manual prerequisite documented in the README, not something `mise bootstrap` can install.

#### Scenario: Packages install via mise bootstrap on Linux
- **WHEN** a contributor on a Debian/Ubuntu-based machine, with `system_packages.managers` restricted to `["apt"]`, runs `mise bootstrap` from the repo root
- **THEN** `curl`, `jq`, `build-essential`, and `libpq-dev` are installed via `apt` and available on `PATH`, and the `brew:` entries are reported as skipped, not attempted

#### Scenario: Packages install via mise bootstrap on macOS
- **WHEN** a contributor on a Mac, with `system_packages.managers` restricted to `["brew"]`, runs `mise bootstrap` from the repo root
- **THEN** `curl`, `jq`, and `libpq` are installed via `brew` and available on `PATH`, the `apt:` entries (including `build-essential`) are reported as skipped, and the README's Development section documents that Xcode Command Line Tools must be installed manually (`xcode-select --install`) for the `pg` gem's native extension to compile

### Requirement: README documents the Development setup command
The system SHALL provide a `README.md` at the repo root containing a **Development** section that assumes `mise` is already installed, links to the official mise installation documentation, documents creating a per-machine `mise.local.toml`, states the command needed to provision every project-declared tool and package, documents the macOS Xcode Command Line Tools prerequisite, and documents how to run `web`, `worker`, and `embedder` as local processes alongside a docker-composed Postgres and Grafana.

#### Scenario: Following the README from a fresh clone
- **WHEN** a contributor with `mise` already installed reads the README's Development section
- **THEN** they find a link to mise's installation docs, instructions for creating `mise.local.toml` with the correct `system_packages.managers` value for their OS, the command (`mise bootstrap`) to run to provision `uv`, `python`, `ansible-core`, `curl`, `jq`, and (on Linux) `build-essential`/`libpq-dev`, and — for macOS — a note to run `xcode-select --install` first

#### Scenario: Following the README to run the app locally
- **WHEN** a contributor follows the README's local-process instructions after bootstrapping
- **THEN** they find the ordered steps: start `postgres`/`grafana` via `docker compose`, run the `mise run db:prepare` task, start `embedder` locally via `uv run uvicorn`, run the `mise run ingest` task, then start `web`/`worker`/`css` via `cd rails_app && bin/dev`

#### Scenario: README has no other sections yet
- **WHEN** `README.md` is inspected
- **THEN** it contains exactly one top-level (`##`) section, Development, and no other top-level sections — the local-process workflow is documented as a subsection within it, alongside the existing Docker-based workflow

## ADDED Requirements

### Requirement: mise tasks provision the local database and local knowledge base
The system SHALL provide a `db:prepare` mise task that prepares the application's databases (schema and the Grafana read-only role) against a running, docker-composed Postgres, and an `ingest` mise task that runs the ingestion job synchronously against a running, docker-composed Postgres and a locally-running `embedder`. Both tasks SHALL run with the repo-root `.env` loaded into their environment.

#### Scenario: db:prepare succeeds against a fresh Postgres
- **WHEN** a contributor runs `mise run db:prepare` after `docker compose up -d postgres` on a Postgres container with no schema yet
- **THEN** the application's databases and the Grafana read-only role are created, without requiring any other manual Rails command

#### Scenario: ingest populates the local knowledge base
- **WHEN** a contributor runs `mise run ingest` after `db:prepare` has succeeded and a local `embedder` process is already running
- **THEN** the ingestion job runs to completion synchronously and the same Postgres database used by locally-run `web`/`worker` processes is populated with modules and embedded chunks

### Requirement: Local process-based web/worker dev workflow
The system SHALL provide a `worker` line in `rails_app/Procfile.dev` (alongside the existing `web` and `css` lines) so `bin/dev` starts all three as local processes, and the Rails application SHALL load the repo-root `.env` automatically via a `development`-only `dotenv-rails` dependency, so required variables (e.g. `OPENAI_API_KEY`) are present for `bin/dev` and any other local Rails process without a container. The `test` environment SHALL NOT load `.env` at all — it must stay hermetic regardless of what a developer's real `.env` contains, and gets a required-but-unused `OPENAI_API_KEY` stand-in instead (real external calls are always stubbed in tests).

#### Scenario: bin/dev starts web, css, and worker together
- **WHEN** a contributor runs `cd rails_app && bin/dev`
- **THEN** `web`, `css`, and `worker` all start as local processes under one `foreman` session

#### Scenario: bin/dev boots successfully without manually exporting secrets
- **WHEN** a contributor with a valid repo-root `.env` (but no shell-exported environment variables) runs `bin/dev`
- **THEN** the `web` and `worker` processes boot successfully, because `dotenv-rails` loaded `OPENAI_API_KEY` and other required variables from the repo-root `.env` automatically on boot, rather than needing them already present in the shell

#### Scenario: dotenv-rails does not activate outside development
- **WHEN** the `web`/`worker` Docker images boot in `RAILS_ENV=production` (as `docker-compose.yml` configures), or `bin/rails test` runs
- **THEN** `dotenv-rails` is not loaded (it is declared only in the Gemfile's `development` group), so production boot never attempts to read a `.env` file that doesn't exist inside the container, and the test suite never picks up real values (e.g. a developer's local `EMBEDDER_URL`) that would break stubs written against the code's own defaults

#### Scenario: bin/rails test runs with zero local setup
- **WHEN** a contributor with no exported environment variables and no `.env` sourced runs `bin/rails test`
- **THEN** the suite boots and runs successfully — `config/environments/test.rb` sets a dummy `OPENAI_API_KEY` stand-in (real OpenAI calls are always stubbed in tests) so `config/initializers/ruby_llm.rb`'s `ENV.fetch` never raises

#### Scenario: locally-run web/worker reach a locally-run embedder
- **WHEN** `EMBEDDER_URL=http://localhost:8000` is set in `.env` and a local `embedder` process is listening on that port
- **THEN** locally-run `web`/`worker` processes successfully call the sidecar's `/embed` and `/rerank` endpoints, and the containerized `web`/`worker`/`embedder` path (which does not read `EMBEDDER_URL`) is unaffected

#### Scenario: locally-run worker actually processes jobs
- **WHEN** a `web` process running in `development` enqueues a job (e.g. `ChatResponseJob` from a real chat message) and a locally-run `worker` process is up
- **THEN** the `development` environment routes the job through Solid Queue (not Rails' default in-process `:async` adapter) and the `worker` process executes it, registering a live `SolidQueue::Process` heartbeat — the same observable behavior `production`'s `worker` container already provides

#### Scenario: a locally-run worker's chat reply appears live, without a page refresh
- **WHEN** a locally-run `worker` process finishes processing a `ChatResponseJob` and broadcasts the assistant's reply via Turbo Streams
- **THEN** a browser viewing that chat (served by the locally-run `web` process) receives the reply live, because `development`'s Action Cable adapter is `solid_cable` (matching `production`), not the single-process-only `async` adapter — the reply is not only visible after a manual page refresh
