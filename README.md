# Ansible Module-Reference RAG Assistant

LLM Zoomcamp capstone project. A chat assistant that answers questions about `ansible.builtin` Ansible modules, grounded in the real, current module documentation instead of what the model remembers from training.

## Problem

Ansible modules change: parameters get renamed, deprecated, replaced. An LLM's knowledge has a training cutoff, so it can confidently answer with information that used to be true and no longer is. I use Ansible often, and this has bitten me more than once — for example, `ansible.builtin.apt_key` is deprecated in favor of `ansible.builtin.deb822_repository`, but a model trained before that change will happily generate a task using `apt_key` anyway.

This app fixes that by retrieving the actual `ansible.builtin` documentation before answering, and citing what it used. Measured on 450 real questions against a fixed ground truth: grounded answers are correct 77.8% of the time, versus 56.9% without retrieval — see [Evaluation](#review-checklist) below for how this is measured.

## Motivation

**Real data over a toy dataset.** I wanted to use a real, changing knowledge source instead of a synthetic one, because the decisions that matter only show up with real data. What happens when a new Ansible release changes a module? How do you keep a ground-truth evaluation set meaningful when the underlying docs it was generated from can change under it? Do you track version history, or only ever serve the latest? None of these questions come up if the data is fake. `ansible.builtin`'s docs are public, structured (`ansible-doc -j` gives clean JSON, no scraping), and change often enough to make these real problems.

**A stack I already know.** The course teaches RAG concepts using a mostly Python stack. I built this in Ruby on Rails with Postgres instead, on purpose — I wanted to focus on learning and applying the course's concepts (retrieval, evaluation, monitoring), not on learning a new language and those concepts at the same time. The one exception: embedding and reranking models. Ruby doesn't have mature equivalents to `sentence-transformers`, so those run in a small Python sidecar service that Rails calls over HTTP.

## Architecture

```
browser ──▶ web (Rails)
              │
              ▼
          postgres (pgvector + full-text search, also the job queue)
              ▲
              │
          worker (Rails + ansible-core) ──▶ embedder (Python, FastAPI)

grafana ──▶ reads postgres directly (read-only)
```

`web` and `worker` never call each other directly — `web` enqueues a background job by writing a row to Postgres, `worker` picks it up from there, does the retrieval + calls OpenAI, and writes the reply back to Postgres. `web`'s UI updates live via Action Cable once that reply lands.

- **`web`** — the Rails app: chat UI, sign-in, monitoring/evaluation pages. Pure Ruby.
- **`worker`** — same Rails codebase, different build target: runs the background jobs (chat responses, weekly document ingestion) and additionally has `ansible-core` installed, since it's the one place that calls `ansible-doc` directly.
- **`postgres`** — one table (`chunks`) holds both a `pgvector` column (semantic search) and a full-text `tsvector` column (keyword search), so hybrid search is one query, not two systems to keep in sync.
- **`embedder`** — a small FastAPI service, Python. Loads the embedding and reranking models once at startup and serves them over HTTP. No Ansible-specific logic — just ML inference, callable by `web` or `worker`.
- **`grafana`** — a pre-provisioned dashboard reading `web`/`worker`'s logged chat data, read-only Postgres access.

Every design decision (and the ones that got revised mid-project, and why) is written up under [`openspec/`](openspec/) — see the [review checklist](#review-checklist) below for links to the specific parts relevant to grading.

## How to review

Two ways to try the app — pick whichever is easier for you.

### Option A: the deployed app

Live at **https://llm-zoomcamp-project.alfonsoalba.com**. Sign in with:

- Email: `llm-zoomcamp@email.com`
- Password: `LeTMeiN!!`

Monitoring dashboard: **https://llm-zoomcamp-project-grafana.alfonsoalba.com** (login: `admin` / `LeTMeiN!!`).

The OpenAI budget behind this deployment is small (a few dollars). If chat stops responding because it ran out, that's why — use Option B instead.

### Option B: run it locally with Docker

You'll need Docker installed. Clone the repo, then create a `.env` file at the repo root with this content (everything works as-is except the OpenAI key, which you need to supply yourself):

```sh
POSTGRES_USER=llm_zoomcamp
POSTGRES_PASSWORD=devpassword
POSTGRES_DB=llm_zoomcamp_development
RAILS_MASTER_KEY=e60e8357993cbb5250e42da19052d5aa
OPENAI_API_KEY=changeme   # <- put your own OpenAI API key here
GRAFANA_ADMIN_PASSWORD=devpassword
GRAFANA_DB_PASSWORD=devpassword
ADMIN_EMAIL=reviewer@example.com
ADMIN_PASSWORD=devpassword
```

(`RAILS_MASTER_KEY` isn't a value you're meant to invent — it's the fixed key that decrypts this repo's committed `rails_app/config/credentials.yml.enc`, which only holds Rails' own boilerplate `secret_key_base`. See [Note for Rails/Ruby developers](#note-for-railsruby-developers) for why every other secret is a plain env var instead.)

Then:

```sh
docker compose up -d --build
```

This builds and runs the same images the production deployment uses — Rails app, worker, Postgres, embedder, Grafana. First boot has an empty knowledge base; populate it once with:

```sh
docker compose exec worker bin/rails runner 'IngestAnsibleModulesJob.perform_now'
```

Takes under a minute, ~1,500 chunks. Then open http://localhost:3000, sign in with the `ADMIN_EMAIL`/`ADMIN_PASSWORD` above, and Grafana at http://localhost:3001.

## Review checklist

Each row links to the OpenSpec capability spec where that requirement is defined — the specs describe *what* the system must do; the archived changes under [`openspec/changes/archive/`](openspec/changes/archive/) describe *how* and *why* it was built that way, including revisions made mid-project.

| What to check | Where | Spec |
|---|---|---|
| Problem description | this README's [Problem](#problem) section | — |
| Retrieval flow (grounded, not free-recall) | ask a question in chat, open "View retrieval details" on the reply | [ansible-retrieval](openspec/specs/ansible-retrieval/spec.md) |
| Retrieval evaluation (multiple strategies compared) | `/evaluation` page — hit-rate/MRR across keyword, vector, hybrid, hybrid+rerank | [ansible-evaluation](openspec/specs/ansible-evaluation/spec.md) |
| LLM evaluation (multiple approaches) | `/evaluation` page — RAG vs. no-RAG accuracy, plus a compositional-task check | [ansible-evaluation](openspec/specs/ansible-evaluation/spec.md) |
| Interface | the chat UI itself | [chat-interface](openspec/specs/chat-interface/spec.md) |
| Ingestion pipeline (automated) | `rails_app/config/recurring.yml` — runs on a schedule, no manual trigger required in normal operation | [ansible-ingestion](openspec/specs/ansible-ingestion/spec.md) |
| Monitoring (feedback + dashboard) | `/monitoring` page, thumbs up/down on replies, Grafana dashboard | [monitoring](openspec/specs/monitoring/spec.md) |
| Containerization | `docker-compose.yml` | [rails-app](openspec/specs/rails-app/spec.md), [postgres-database](openspec/specs/postgres-database/spec.md), [embedding-service](openspec/specs/embedding-service/spec.md) |
| Reproducibility | [Development setup](#development-setup) below | [dev-toolchain](openspec/specs/dev-toolchain/spec.md) |
| Bonus: hybrid search + reranking | same as retrieval flow above | [ansible-retrieval](openspec/specs/ansible-retrieval/spec.md) |
| Bonus: cloud deployment | Option A above — the live URL | [deployment](openspec/specs/deployment/spec.md) |

**Not implemented**: query rewriting (the third best-practices bonus point). Everything else above is real and checkable.

Real numbers from the current evaluation run (`rails_app/data/eval_results.json`, 450 questions):

| Retrieval strategy | Hit rate | MRR |
|---|---|---|
| Keyword only | 0.2% | 0.1% |
| Vector only | 63.1% | 45.9% |
| Hybrid | 61.3% | 45.3% |
| Hybrid + rerank | 71.6% | 53.3% |

| | Accuracy |
|---|---|
| With retrieval (RAG) | 77.8% |
| Without retrieval | 56.9% |

<!-- screenshots to add once the app is reviewed end-to-end:
- chat interface with a real answer + citations popup open
- /monitoring page
- /evaluation page
- Grafana dashboard
-->

## Development setup

This project uses [mise](https://mise.jdx.dev/) to manage all local development tools and system packages. Install `mise` itself first: https://mise.jdx.dev/installing-mise.html

Before running anything else, create a `mise.local.toml` file at the repo root (gitignored, personal to your machine) restricting `mise` to your platform's package manager:

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

This is required, not optional. Without it, `mise` tries to install *every* declared package manager's packages — including bootstrapping Homebrew on Linux (or the reverse) for entries meant for the other platform.

**macOS only:** install Xcode Command Line Tools before bootstrapping (`xcode-select --install`) — the `pg` gem needs a C compiler to build its native extension.

Once `mise.local.toml` is in place:

```sh
mise bootstrap
```

This provisions Ruby and everything else declared in `mise.toml` — no separate install step needed.

### Running the app

Copy `.env.example` to `.env` and fill in real values (or use the snippet in [Option B](#option-b-run-it-locally-with-docker) above). Then:

```sh
docker compose up -d --build
```

`web` and `worker` build from the same Rails codebase (`rails_app/`) via two Docker build targets — `worker` additionally has `ansible-core` installed. Database setup runs automatically on first boot (`bin/docker-entrypoint`) — nothing to run by hand.

Once the app is up, sign in with your `ADMIN_EMAIL`/`ADMIN_PASSWORD` at http://localhost:3000. Every page requires signing in — there's no registration, by design (see [authentication](openspec/specs/authentication/spec.md)). The monitoring dashboard is at http://localhost:3001, and `/monitoring` and `/evaluation` are in-app pages under the main nav.

### Populating the knowledge base (ingestion)

`worker` runs `IngestAnsibleModulesJob` on a recurring weekly schedule (Solid Queue, `rails_app/config/recurring.yml`): fetches every `ansible.builtin` module's docs via `ansible-doc`, splits them into chunks (one per parameter, named example, return value, plus one module overview), embeds each chunk via the `embedder` sidecar, and stores the result in Postgres. Each run fully replaces the previous data set, atomically — the app is never left with an empty or half-populated knowledge base mid-run.

To populate the database immediately instead of waiting for the first scheduled run:

```sh
docker compose exec worker bin/rails runner 'IngestAnsibleModulesJob.perform_now'
```

Takes well under a minute, ~71 modules and ~1,500 chunks.

### Running locally without Docker rebuilds

`docker compose up -d --build` is the production-equivalent path — full container rebuilds on every code change. For faster iteration, `web`/`worker`/`embedder` can run as local processes instead, while Postgres and Grafana stay in `docker compose`:

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

Copy `.env.example` to `.env` at the repo root, same as the Docker path — `bin/dev`, `rails console`, `rails runner`, and tests all load it automatically via the `dotenv-rails` gem. `EMBEDDER_URL` in `.env.example` defaults to `http://localhost:8000`, matching step 3 — it's only read by locally-run `web`/`worker` processes, not the containerized path.

### Running the evaluation suite

```sh
cd rails_app
bin/rails eval:all
```

This regenerates ground truth, then runs retrieval, LLM, and compositional evaluation against it, and writes `data/eval_results.json` — what's shown at `/evaluation`. Add `SKIP_GROUND_TRUTH=1` to reuse the existing `data/ground_truth.csv` instead of regenerating it, and `EVAL_SAMPLE_SIZE=N` to limit the (slower, real-API-call) LLM evaluation to a sample.

A full run makes hundreds of real OpenAI API calls — it can take a few hours and cost around $4. `EVAL_SAMPLE_SIZE` is the way to cut that down if you just want to confirm the pipeline works.

Ground truth is pinned to a specific `ansible-core` version at generation time and only regenerated deliberately — not on every ingestion refresh — so evaluation numbers stay comparable run over run. See [ansible-evaluation](openspec/specs/ansible-evaluation/spec.md) for why.

## Note for Rails/Ruby developers

If you're an experienced Rails developer and something here looks off: this project was built with [Claude Code](https://claude.com/claude-code), driven through [OpenSpec](https://github.com/Fission-AI/OpenSpec) (every feature went through a proposal → design → tasks → implementation cycle — see [`openspec/changes/archive/`](openspec/changes/archive/) for the full history, including decisions that got revised mid-project once implementation surfaced a wrong assumption).

The priority throughout was applying the LLM Zoomcamp's concepts — retrieval, evaluation, monitoring, deployment — not building the most idiomatic or best-architected Rails app possible. Some choices trade architectural cleanliness for speed or simplicity where a from-scratch senior Rails project might do things differently.

One deliberate example: every secret in this app is a plain environment variable, not a Rails encrypted credential. Partly for consistency (Docker/Kamal both inject env vars naturally), but also because it makes review easier — there's no separate secure channel needed to hand a reviewer a master key for real secrets. The one Rails-credentials key that *is* shared above (`RAILS_MASTER_KEY`) only decrypts an unused, boilerplate `secret_key_base`.
