## Context

This is the second infrastructure piece of the Ansible RAG capstone, and the first piece of actual application logic (the first change, `setup-postgres-compose`, only stood up Postgres). Per the architecture captured in `PLAN.md`, the embedder is deliberately scoped to **ML serving only** — no CLI/subprocess responsibilities, no `ansible-core` (that lives in a separate `worker` image, added in a later change). Nothing in the repo depends on Rails existing yet, and nothing here should either: the embedder must be fully buildable, runnable, and testable via direct HTTP calls in complete isolation.

## Goals / Non-Goals

**Goals:**
- A FastAPI service exposing `POST /embed` and `POST /rerank`, backed by `sentence-transformers` (`all-MiniLM-L6-v2`, 384-dim) and `CrossEncoder` (`cross-encoder/ms-marco-MiniLM-L-6-v2`) respectively.
- Both models loaded exactly once, at process startup — not per-request, not lazily on first call.
- A healthcheck that reflects true readiness (models loaded into memory), not just "the HTTP process is up."
- Runnable via `docker compose up -d embedder` with no other services required, and independently verifiable via `curl` from the host (or the `test.sh` script) before any Rails code exists.

**Non-Goals:**
- No `ansible-doc`/`ansible-core` — that's the `worker` image's job, in a separate change.
- No authentication/authorization on the endpoints — the service is published to `localhost` on the host machine for local testing/peer review, but not to any public-facing network interface; this is a local/dev/grading context, not a production deployment.
- No GPU support — CPU inference is the assumed target (matches a local/dev/small-cloud-instance deployment; not a performance-tuning exercise for this change).
- No batching/throughput tuning for ingestion-scale loads (~1,400 chunks) — that's a concern for the ingestion change that consumes this endpoint; this change just needs `/embed` to correctly handle an arbitrary-size batch, not to be fast at a specific scale.

## Decisions

**1. Models are downloaded at Docker *build* time, not at container *first-request* time.**
- The Dockerfile runs a `RUN python -c "from sentence_transformers import SentenceTransformer, CrossEncoder; SentenceTransformer('all-MiniLM-L6-v2'); CrossEncoder('cross-encoder/ms-marco-MiniLM-L-6-v2')"`-style step during the image build, baking the model weights into an image layer.
- Alternative considered: let the models download lazily on first use/startup. Rejected — it would mean the container needs network egress at *runtime* to reach Hugging Face's model hub, which is a real risk in a grading/reproducibility context (peer reviewers' environments, CI, or a submission deadline where the hub is briefly unreachable, shouldn't be able to break `docker compose up`). Baking weights into the image trades a slower/larger build for a deterministic, network-independent runtime start — directly supports the Reproducibility rubric criterion.
- **Gap found during implementation, not anticipated at design time**: baking the weights in at build time is not sufficient on its own. `sentence-transformers`/`huggingface_hub` still issue `HEAD` requests to `huggingface.co` at *runtime* startup (checking for metadata/updates), even though the weights are already present locally from the build step. Verified directly: running the built image with `podman run --network none` showed repeated `Temporary failure in name resolution` errors with exponential backoff (~46s total across two files) and the container never reached `healthy`. Fixed by setting `ENV HF_HUB_OFFLINE=1` in the Dockerfile — but only *after* the build-time model-download `RUN` step (setting it earlier would make that same download step fail, since it also goes through `huggingface_hub`). Re-verified with the same `--network none` test: no network errors, `healthy` in ~7s, matching the original goal this decision was supposed to guarantee.

**2. Single Uvicorn worker process, not multiple.**
- The Dockerfile's `CMD` runs Uvicorn without `--workers N`. Alternative considered: multiple worker processes for higher request throughput. Rejected for this service — each worker process would load its own independent copy of both models into memory (each likely tens to low-hundreds of MB), multiplying memory footprint for no benefit at this project's expected load (a handful of concurrent chat requests plus one weekly batch ingestion run, not a high-QPS production service). Concurrency within the single process is handled by FastAPI/Starlette running the (CPU-bound, synchronous) model inference calls in its default thread pool, so one slow request doesn't block the event loop for others — sufficient for this scale.

**3. Published host port, configurable via `EMBEDDER_PORT` (default `8001`).**
- The `embedder` service maps `${EMBEDDER_PORT:-8001}:8000`, matching the `POSTGRES_PORT` pattern already established in `docker-compose.yml`. Revised from an earlier version of this design that kept the service off the host entirely for a smaller exposure surface. Reasoning for the reversal: this project needs to be directly `curl`-able from the host for the verification script (`embedder/test.sh`, decision 6 below) and for peer reviewers/graders to poke at it without Docker-networking knowledge — a real, concrete need that outweighs a theoretical exposure-surface argument with no actual threat model behind it in a local/dev/grading context. Revisit only if this service is ever deployed somewhere with a genuinely different network boundary (e.g. the cloud-deployment bonus milestone).

**4. Healthcheck hits a dedicated `/health` endpoint using Python's stdlib `urllib`, not `curl`.**
- Slim Python base images don't ship `curl` by default, and installing it is an extra `apt-get` layer for a single healthcheck call. `HEALTHCHECK CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=2)"` avoids that dependency entirely. `/health` only returns `200` once both models have finished loading into memory (tracked via a simple module-level flag set after the startup model-loading code completes) — so "healthy" genuinely means "ready to serve," not just "process started."

**5. Package/dependency management via `uv`.**
- Matches the `uv`/`mise` tooling already used across the user's other course repos (per `PLAN.md`). `pyproject.toml` + `uv.lock`, Dockerfile installs via `uv sync --frozen` (or equivalent) rather than a loose `pip install -r requirements.txt`, for reproducible, lockfile-pinned dependency resolution.

**6. Verification via a `bash` + `curl` + `jq` script, not a `pytest` suite.**
- `embedder/test.sh` runs each spec scenario as a `curl` call against a live, running instance, asserting on the JSON response via `jq` and exiting non-zero on the first failure. Alternative considered: a `pytest` suite using FastAPI's `TestClient`. Rejected for this change — a `TestClient`-based suite would exercise the app in-process (no real Docker networking, no real startup sequence), which doesn't actually prove the container/healthcheck/port-mapping work end-to-end the way this project needs proven; it would also add `pytest`/`httpx` as extra dependencies for a two-endpoint service. A `curl`-based script instead tests the *real* deployed artifact exactly the way a peer reviewer or grader would poke at it, needs nothing beyond `curl`/`jq` (both near-universally available), and is a near-1:1 translation of the manual verification steps already in this change's `tasks.md`, so it costs little extra to write.

**7. Python 3.14, matching the project's `mise.toml` convention.**
- `mise.toml`'s `"python" = "latest"` resolves to 3.14.6 on the dev-toolchain-bootstrap-provisioned machine. Verified directly (not assumed) that `sentence-transformers`/`torch` have working 3.14 wheels via `uv venv --python 3.14` + a dry-run install (resolved `torch==2.13.0` cleanly). No reason to target an older version like 3.12 once that was actually checked instead of defaulted to.

**8. `torch` pinned to CPU-only wheels via a `[tool.uv.sources]`/`[[tool.uv.index]]` override, with `torch` listed as a direct dependency.**
- Plain `torch` (and therefore `sentence-transformers`, which pulls it in transitively) resolves to the default PyPI wheel, which bundles the full CUDA/`nvidia-*` stack (`nvidia-cufft`, `nvidia-cusolver`, `nvidia-cusparse`, `nvidia-nccl`, etc.) — several GB of libraries this CPU-only, no-GPU service (see Non-Goals) never uses. Verified by resolving `sentence-transformers` in a scratch `uv` project both ways: default resolution pulled ~15 `nvidia-*` packages; adding
  ```toml
  [[tool.uv.index]]
  name = "pytorch-cpu"
  url = "https://download.pytorch.org/whl/cpu"
  explicit = true

  [tool.uv.sources]
  torch = [{ index = "pytorch-cpu" }]
  ```
  resolved `torch==2.13.0+cpu` with zero `nvidia-*` packages instead — but only once `torch` was *also* added as an explicit direct dependency (e.g. `"torch>=2.13.0"` in `[project.dependencies]`) alongside `sentence-transformers`; the source override was silently ignored when `torch` was left purely transitive. This isn't optional/cosmetic — it directly affects Dockerfile build time and final image size, both relevant to the "bake weights in at build time" decision above (decision 1) not becoming untenably slow/large.

**9. Request/response contract preserves input order positionally.**
- `POST /embed {texts: [...]}` → `{embeddings: [[...], ...]}` where `embeddings[i]` corresponds to `texts[i]`.
- `POST /rerank {query: "...", candidates: [...]}` → `{scores: [...]}` where `scores[i]` corresponds to `candidates[i]`.
- No candidate/text IDs required in the contract — callers (Rails, in a later change) are responsible for zipping results back with their own IDs by position. Keeps the sidecar's contract minimal and stateless.

## Risks / Trade-offs

- **[Risk] Baking model weights into the image makes builds slower and images larger** → Mitigation: accepted trade-off for reproducibility (no runtime network dependency); Docker layer caching means this cost is paid once per model-version bump, not on every build.
- **[Risk] CPU-only inference may be slow for large batches** (e.g. ingestion's ~1,400 chunks) → Mitigation: out of scope here — `/embed` just needs to correctly handle arbitrary batch sizes; actual throughput at ingestion scale is something the ingestion change can measure and, if needed, address later (e.g. client-side chunked batching) without changing this service's contract.
- **[Trade-off] No auth on endpoints, and the port is now published to the host** → acceptable because it's bound to `localhost` on a single dev/grading machine, not a public interface, and there's no sensitive data behind these endpoints (just embedding/reranking math); revisit if this sidecar is ever deployed somewhere with a genuinely different network boundary (e.g. the cloud-deployment bonus milestone), where a public IP would need real access control.
- **[Trade-off] Single worker process caps request concurrency** → acceptable at this project's expected scale (interactive chat + one weekly batch job, not concurrent high-QPS traffic); revisit only if profiling later shows this as an actual bottleneck.

## Migration Plan

- Purely additive: new `embedder/` directory (`main.py`, `pyproject.toml`, `uv.lock`, `Dockerfile`) and one new service block appended to the existing `docker-compose.yml`. The existing `postgres` service definition is untouched.
- Rollout: `docker compose up -d embedder`, wait for `docker compose ps` to show `healthy`, then run `embedder/test.sh` against it.
- Rollback: `docker compose down embedder` (or full `docker compose down`) and remove the added files/compose block. No data/state to worry about — this service is stateless.

## Open Questions

- Exact Dockerfile base image (e.g. `python:3.14-slim` vs an official `uv` base image) — Python version itself is now resolved (3.14, decision 7); which base image ships it is still an implementation detail for the tasks phase.
- None of the above are blocking; revisit CPU throughput and auth posture only if later changes (ingestion, cloud deployment) surface a concrete problem.
