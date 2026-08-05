## Context

See proposal.md for motivation. Current topology (`docker-compose.yml`):

```
postgres (healthy) ──▶ prepare_db (run, exit 0) ──▶ web
embedder (healthy) ───────────────────────────────▶ web
                                                 └──▶ worker
```

`web` and `worker` are Dockerfile targets `web`/`worker` in a shared `base` stage (`rails_app/Dockerfile`), so any change to boot behavior added in `base` reaches both images automatically. Neither image currently has an `ENTRYPOINT`; both rely solely on `CMD`. Rails 8's default scaffold generates a `bin/docker-entrypoint` that runs `db:prepare` before `exec "$@"` — this project's Dockerfile never adopted it, using the separate `prepare_db` service instead (see the `prepare_db` rationale in CLAUDE.md, written before the `service_completed_successfully` gap was discovered under podman).

Two things were verified empirically this session and materially shape the design below:

1. **`service_completed_successfully` is unreliable here.** Already documented in CLAUDE.md's podman-quirks section: podman-compose's `--requires`-based implementation only guarantees start order, not actual exit. `prepare_db`'s correctness has only ever been confirmed by manual sequencing.
2. **`db:prepare`'s fresh-database path takes no lock.** Read `activerecord-8.1.3.1`'s `migration.rb`: `Migrator#migrate`/`#up`/`#down` wrap themselves in `with_advisory_lock` (a Postgres advisory lock), but `DatabaseTasks#load_schema` — the path `db:prepare` takes on a database with no `schema_migrations` yet — does not; it just `load`s `db/schema.rb` directly. Reproduced live: two concurrent `bin/rails runner` processes loading `db/schema.rb` against a disposable scratch database raced, and one crashed with `PG::UndefinedTable: relation "tool_calls" does not exist` (a partially-created schema collision) while the other completed cleanly.

Finding (2) means "just move `db:prepare` into each container's own entrypoint" is not safe on its own if `web` and `worker` can both start it around the same time on a fresh volume — which is exactly what happens today, since both currently only depend on `prepare_db`+`embedder`, symmetrically.

## Goals / Non-Goals

**Goals:**
- Retire dependence on `service_completed_successfully`.
- Make `web`'s dependency on `worker` explicit and enforced at the compose level, not just true-in-practice.
- Preserve the "no manual Rails command" guarantee for non-developer reviewers.
- Preserve (and make actually-load-bearing rather than incidentally-true) the "database preparation does not race" guarantee.

**Non-Goals:**
- No change to how migrations themselves work, or to the multi-database (`primary`/`queue`/`cache`/`cable`) topology.
- No general worker-liveness monitoring after startup — `depends_on` only gates initial start order; a worker that crashes ten minutes into a running stack is out of scope here (compose has no primitive for "stop `web` if a sibling later becomes unhealthy").
- Not adding Postgres advisory locking around `db:prepare` — see Decisions below for why ordering, not locking, is the chosen fix for the race.

## Decisions

### 1. `bin/docker-entrypoint` in the shared `base` Dockerfile stage, not per-target

The script is added once in `base`, and both `web`'s and `worker`'s `ENTRYPOINT` point to it, `CMD` unchanged (`bin/rails server -b 0.0.0.0` / `bin/jobs` respectively — entrypoint scripts receive `CMD` as `"$@"` and `exec` it after their own setup). One file, no duplication, matches this project's existing single-Dockerfile-two-targets rationale.

### 2. Worker healthcheck via Solid Queue's own heartbeat table, not a process-liveness check

`bin/rails runner "exit(SolidQueue::Process.where('last_heartbeat_at > ?', 2.minutes.ago).exists? ? 0 : 1)"` (exact freshness window confirmed at apply time against Solid Queue's actual default `process_heartbeat_interval`, currently unoverridden in `config/queue.yml` — gem default is 60s, so a 2-minute window gives one missed-heartbeat's slack before flapping unhealthy).

Alternative considered: `pgrep -f bin/jobs` (process-exists check). Rejected — it would report healthy the instant the process forks, before Solid Queue has even connected to Postgres or started polling, which is exactly the gap that let today's incident happen silently. The heartbeat table is true liveness (actively processing), not just "a process exists," and it's queried with a tool already in the image (`bin/rails runner`), matching every other service's healthcheck convention (`pg_isready`, Python `urllib`, Ruby `net/http`).

### 3. `web depends_on worker: service_healthy` — the *intended* fix for the race, not a verified one in this sandbox

The design intent: `web`'s container would not be created until `worker` reports healthy, and `worker` cannot report healthy until its own entrypoint's `db:prepare` has completed and Solid Queue has booted far enough to write a heartbeat row — making `worker` the guaranteed first mover on a fresh database. `web`'s own entrypoint still calls `db:prepare` too (kept for defense-in-depth and so `web` remains startable standalone, e.g. `docker compose up -d web` after `worker` already prepared the schema in a prior run) — once the schema already exists, that call takes the locked `db:migrate` path (a no-op "nothing to migrate" check) rather than the unlocked `load_schema` path.

**This is what a conformant Docker Compose implementation would enforce. It is not what this sandbox's podman-compose actually enforces** — see "Verified during implementation" below. The decision to ship this dependency edge anyway, accepting the residual race as a documented edge case rather than adding real locking, is unchanged; only the justification changed from "the ordering is guaranteed" to "the ordering is declared, and is what a correct implementation would guarantee."

### 4. `worker` depends directly on `postgres: service_healthy` (currently only transitive via `prepare_db`)

With `prepare_db` gone, `worker` needs its own direct edge to `postgres` (it already keeps `embedder: service_healthy`, unchanged — needed for ingestion's embedding calls, unrelated to this change).

## Verified during implementation

Two assumptions in Decision 3 above were empirically tested live during `/opsx:apply` and found wrong, in a way consistent with (and now extending) CLAUDE.md's existing podman-quirks documentation:

1. **`service_healthy` does not gate container start order in this sandbox's podman-compose, any more than `service_completed_successfully` does.** Bringing up the real stack, `worker`'s container started at `00:06:08.561` and `web`'s started at `00:06:09.752` — 1.2 seconds later, nowhere near enough time for `worker`'s entrypoint to run `db:prepare`, boot Solid Queue, and record a heartbeat (the healthcheck has a 30s `start_period`). Confirmed more directly with a controlled fault-injection test: an isolated worker container running `sleep infinity` (so it never boots Solid Queue and never passes its healthcheck) was confirmed `unhealthy` by Podman after its retry threshold elapsed, then a second isolated container with `--requires=<that unhealthy container>` was started anyway and reached `running` state without being blocked. `--requires` — what podman-compose compiles every `depends_on` condition down to — only guarantees the dependency container was *started*, never that it passed its healthcheck.
2. This means the "fail loud" behavior described in proposal.md (a broken `worker` should keep `web` from starting at all) **does not actually happen in this sandbox**. `web` will start and serve traffic regardless of `worker`'s health. It would fail loud under a Docker Compose implementation that actually blocks on `service_healthy`.

**Decision, confirmed with the user:** keep `docker-compose.yml` exactly as designed — it correctly declares the intended dependency graph, and would behave as designed under real Docker Compose or a more complete Podman. Document this as a third entry in CLAUDE.md's podman-quirks section (alongside the existing `service_completed_successfully` and `--requires`-graph-resolution entries) rather than adding application-level enforcement (e.g. a lock, or a readiness poll independent of compose) to work around a sandbox-only limitation. This mirrors exactly how `service_completed_successfully` was already handled before this change.

A secondary, unrelated finding surfaced while building the fault-injection test: the heartbeat healthcheck query (`SolidQueue::Process.where('last_heartbeat_at > ?', ...).exists?`) is not scoped to the container's own process — it is satisfied by *any* live Solid Queue process sharing the same physical queue database, of which there is normally only one (this project runs a single `worker` container). Not a bug worth fixing for this topology, but worth knowing if the project ever ran multiple worker replicas against the same database.

## Risks / Trade-offs

- **[Risk]** The `db:prepare` race (Context, finding 2) is only prevented if `web`'s entrypoint never runs concurrently with `worker`'s on a fresh volume. Given finding 1 above, the `depends_on` edge does not actually guarantee this in this sandbox — only the ~1-2 second gap between podman-compose issuing `worker`'s and `web`'s `podman run` commands (itself just an artifact of sequential script execution, not a real wait) stands between the current behavior and a repeat of the crash reproduced in Context. → Accepted as a rare, documented edge case (requires a truly fresh, empty volume — the very first `docker compose up` ever — and both entrypoints hitting the unlocked `load_schema` window within roughly that gap) rather than adding Postgres advisory locking, per direction from the user. If hit, the affected container exits; remediation is to re-run `docker compose up -d` (may require dropping the partially-created databases first if the schema was left inconsistent, then retrying) since there is no `restart` policy configured on `web`/`worker` to auto-retry.
- **[Risk]** The "fail loud" goal does not hold in this sandbox (Verified during implementation, finding 1). A broken `worker` will not stop `web` from starting or serving traffic here, though it would under a conformant Docker Compose. → Accepted; documented as a podman quirk rather than worked around at the application level.
- **[Risk]** `depends_on: service_healthy` only ever gates startup order in principle, let alone in this sandbox; a worker that dies after both containers are already up won't retroactively stop `web` under any implementation. → Out of scope (see Non-Goals); this design targets the startup-race incident class, not general runtime liveness.
- **[Trade-off]** `web`'s entrypoint keeps calling `db:prepare` even though `worker` will almost always have already done it. Redundant in the common case, but keeps `web` independently startable (matches the existing "no manual Rails command" requirement scenario, which doesn't mention `worker` at all) and costs one fast no-op `schema_up_to_date?` check per boot.
