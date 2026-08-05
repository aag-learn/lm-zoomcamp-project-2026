## Why

Two live incidents this session exposed the same root cause: the compose topology doesn't actually encode the real dependencies between services. First, `podman-compose up` failed to start `worker` at all because of a Podman `--requires` graph-resolution bug — but nothing in the topology would have caught this even if it *had* worked, because `web` has no dependency on `worker`. Second, when `worker` was stuck, `web` came up healthy anyway and silently accepted chat messages that never got replies, with zero visible error to a reviewer. Separately, `prepare_db`'s ordering guarantee already rests on `service_completed_successfully`, which CLAUDE.md documents as not actually working under podman-compose in this sandbox — its correctness has only ever been confirmed by manual sequencing, not the compose file itself.

## What Changes

- Remove the `prepare_db` one-shot service. Add a `bin/docker-entrypoint` script (added to the shared `base` Dockerfile stage, so both `web` and `worker` images get it for free) that runs `bin/rails db:prepare` before each container's real command (`bin/rails server` / `bin/jobs`). This retires reliance on `service_completed_successfully`.
- Add a real healthcheck to the `worker` service, based on Solid Queue's own heartbeat (`solid_queue_processes.last_heartbeat_at`), using `bin/rails runner` — matching every other service's "use a tool already in the image" healthcheck convention.
- **BREAKING** (compose topology): `web` now depends on `worker: service_healthy` instead of starting independently. If `worker` fails to become healthy, `web` will not start. This is an intentional fail-loud choice — a fully down stack is more legible to a non-developer reviewer than a half-working one where chat silently never responds.
- Sequencing note carried into design.md: `db:prepare`'s fresh-database path takes no advisory lock (unlike `db:migrate`), so concurrent `web`+`worker` entrypoints running `db:prepare` against a fresh volume would race — confirmed by live reproduction against a disposable scratch database. The `web depends_on worker: service_healthy` ordering is what prevents this race in practice (worker is always the first mover), not a new locking mechanism. This makes the healthcheck a correctness prerequisite for the entrypoint change, not just a nice-to-have — the reason both are one bundled change.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `rails-app`: "Application databases are prepared automatically" changes mechanism (entrypoint script, not a separate one-shot service) while keeping its no-race guarantee — now satisfied by dependency ordering rather than a completion-signal. "Worker container runs a background job processor" gains a heartbeat-based healthcheck. New requirement: web only starts once worker is confirmed healthy.

## Impact

- `docker-compose.yml`: remove `prepare_db` service; add `worker.healthcheck`; change `web.depends_on` from `prepare_db: service_completed_successfully` to `worker: service_healthy`; `worker.depends_on` drops `prepare_db`, keeps `embedder: service_healthy` and adds `postgres: service_healthy` directly (currently transitive via `prepare_db`).
- `rails_app/Dockerfile`: add `COPY bin/docker-entrypoint /app/bin/docker-entrypoint` (or equivalent) in the `base` stage; set `ENTRYPOINT` on both `web` and `worker` targets.
- New file: `rails_app/bin/docker-entrypoint`.
- `openspec/specs/rails-app/spec.md`: requirement updates described above.
- No Ruby application code changes — this is pure container/orchestration topology.
