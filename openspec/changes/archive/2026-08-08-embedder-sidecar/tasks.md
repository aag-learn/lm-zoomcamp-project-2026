## 1. Project scaffold

- [x] 1.1 Create `embedder/` directory with `pyproject.toml` (`uv` project, Python 3.14) declaring dependencies: `fastapi`, `uvicorn`, `sentence-transformers`, `torch` (direct, required for the CPU-only override below to apply)
- [x] 1.1a Add `[[tool.uv.index]]` (`pytorch-cpu`, `https://download.pytorch.org/whl/cpu`, `explicit = true`) and `[tool.uv.sources]` (`torch = [{ index = "pytorch-cpu" }]`) to `embedder/pyproject.toml`
- [x] 1.2 Run `uv lock` and confirm `embedder/uv.lock` resolves `torch` as `+cpu` with no `nvidia-*` packages

## 2. FastAPI application

- [x] 2.1 Create `embedder/main.py`: load `SentenceTransformer("all-MiniLM-L6-v2")` and `CrossEncoder("cross-encoder/ms-marco-MiniLM-L-6-v2")` once at module/startup level, tracking a `models_loaded` readiness flag
- [x] 2.2 Implement `POST /embed` — accepts `{"texts": [...]}`, returns `{"embeddings": [[...], ...]}` preserving input order, handles an empty list
- [x] 2.3 Implement `POST /rerank` — accepts `{"query": "...", "candidates": [...]}`, returns `{"scores": [...]}` preserving input order, handles an empty list
- [x] 2.4 Implement `GET /health` — returns success only once `models_loaded` is true

## 3. Dockerfile

- [x] 3.1 Create `embedder/Dockerfile`: install dependencies via `uv sync --frozen`
- [x] 3.2 Add a build step that downloads/caches both model weights at image-build time (e.g. `RUN python -c "from sentence_transformers import SentenceTransformer, CrossEncoder; SentenceTransformer('all-MiniLM-L6-v2'); CrossEncoder('cross-encoder/ms-marco-MiniLM-L-6-v2')"`)
- [x] 3.2a Set `ENV HF_HUB_OFFLINE=1` after the model-download step (not before) — verified via `podman run --network none` that without this, startup still attempts `HEAD` requests to huggingface.co and retries with backoff instead of starting cleanly
- [x] 3.3 Set `CMD` to run Uvicorn as a single worker process (no `--workers` flag) on port 8000
- [x] 3.4 Add a `HEALTHCHECK` using Python's stdlib `urllib` (no `curl` dependency) against `GET /health`
- [x] 3.5 Verify `ansible-core` is not installed anywhere in the built image

## 4. Compose integration

- [x] 4.1 Add an `embedder` service to `docker-compose.yml`: `build: ./embedder`, `ports: ["${EMBEDDER_PORT:-8001}:8000"]`, healthcheck matching the Dockerfile's (using `CMD-SHELL` form, not exec-array `CMD` — the latter hit a `podman-compose` quoting bug that mangled nested quotes into a shell syntax error; `CMD-SHELL` avoids it and matches the `postgres` service's existing style)
- [x] 4.2 Add `EMBEDDER_PORT` (default `8001`) to `.env.example`
- [x] 4.3 Confirm `docker compose up -d embedder` boots the service and `docker compose ps` reports `healthy` once models finish loading

## 5. Automated verification script

- [x] 5.1 Create `embedder/test.sh` (`bash` + `curl` + `jq`), reading the base URL from an `EMBEDDER_URL` env var defaulting to `http://localhost:8001`
- [x] 5.2 Check: `POST /embed` with 2+ texts returns embeddings in matching order, each 384-dimensional
- [x] 5.3 Check: `POST /embed` with an empty list returns an empty list without error
- [x] 5.4 Check: `POST /rerank` with a query and 2+ candidates returns scores in matching order, with the more relevant candidate scoring higher
- [x] 5.5 Check: `POST /rerank` with an empty candidate list returns an empty list without error
- [x] 5.6 Check: `GET /health` returns success (only meaningful once the service is up; script should fail clearly if run before `docker compose ps` shows healthy)
- [x] 5.7 Script prints a clear pass/fail per check and exits non-zero on any failure
- [x] 5.8 `chmod +x embedder/test.sh`

## 6. Verification

- [x] 6.1 Run `embedder/test.sh` against the running `embedder` service — confirm all checks pass
- [x] 6.2 Temporarily break one contract (e.g. swap `/embed`'s response order) and confirm `embedder/test.sh` fails and reports it, then revert — this also caught a real bug in the test script itself: the original `/embed` order check used exact vector equality, which produced a false failure from harmless batch-padding floating-point noise even on *correct* code (verified by accidentally testing against a stale, not-yet-rebuilt container). Replaced with a cosine-similarity check (threshold 0.99), calibrated empirically: same-text similarity ~1.0, genuinely-different-text similarity ~0.64 for the sample sentences used
- [x] 6.3 Restart the container (`docker compose restart embedder`) and confirm no runtime network call is made to Hugging Face (models load from the image, not the network) — e.g. by checking logs or running with network disabled
- [x] 6.4 Inspect installed packages in the built image (e.g. `docker compose exec embedder uv pip list` or `pip list`) — confirm `ansible-core` is absent
