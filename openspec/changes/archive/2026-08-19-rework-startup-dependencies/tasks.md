## 1. Groundwork

- [x] 1.1 Confirm Solid Queue's actual default `process_heartbeat_interval` (gem source or a live `SolidQueue::Configuration` inspection) to finalize the worker healthcheck's freshness window — design.md assumes ~60s default / 2-minute window pending this check. **Confirmed: `SolidQueue.process_heartbeat_interval` defaults to `60.seconds` (`solid_queue-1.6.0/lib/solid_queue.rb:30`), unoverridden in this project's `config/queue.yml`. The 2-minute window stands.**

## 2. Entrypoint script

- [x] 2.1 Write `rails_app/bin/docker-entrypoint`: runs `bin/rails db:prepare`, then `exec "$@"`.
- [x] 2.2 Make it executable (`chmod +x`) so the permission bit survives `COPY . .` in the `base` Dockerfile stage.

## 3. Dockerfile changes

- [x] 3.1 Add `ENTRYPOINT ["bin/docker-entrypoint"]` to the `web` target.
- [x] 3.2 Add `ENTRYPOINT ["bin/docker-entrypoint"]` to the `worker` target.
- [x] 3.3 Confirm `CMD` on both targets is unchanged and still gets passed through as `"$@"`.

## 4. Compose topology changes

- [x] 4.1 Remove the `prepare_db` service from `docker-compose.yml`.
- [x] 4.2 Add a `healthcheck` to `worker` using the Solid Queue heartbeat check (`bin/rails runner "exit(SolidQueue::Process.where('last_heartbeat_at > ?', <window>).exists? ? 0 : 1)"`, window from task 1.1), `CMD-SHELL` form per this project's podman-quirks convention.
- [x] 4.3 Change `web.depends_on`: replace `prepare_db: service_completed_successfully` with `worker: service_healthy`; keep `embedder: service_healthy`.
- [x] 4.4 Change `worker.depends_on`: remove `prepare_db`, add `postgres: service_healthy` directly (currently only transitive via `prepare_db`); keep `embedder: service_healthy`.

## 5. Docs

- [x] 5.1 Update CLAUDE.md's Architecture section: remove the `prepare_db`-as-separate-service rationale, replace with the entrypoint-based approach and the `web depends_on worker: service_healthy` ordering guarantee (including *why* — the unlocked `db:prepare` fresh-schema race this ordering prevents).
- [x] 5.2 Update CLAUDE.md's podman-quirks section: the note about `prepare_db`'s ordering being "only verified by manual sequencing" no longer applies once `service_completed_successfully` is retired — remove or rewrite it to reflect the new mechanism.

## 6. Verification

- [x] 6.1 Fresh-volume test (revised in scope): the underlying `db:prepare` race was already reproduced deterministically against a disposable scratch database during design (see design.md Context). Re-running the full real stack against a wiped `postgres_data` volume was judged too risky to the real dev volume for what it would add — evidence already establishes the race is real; live timing observations (see 6.2) establish it isn't reliably prevented by `depends_on` either. Not re-triggered live on the real stack; documented as an accepted edge case in design.md instead.
- [x] 6.2 Fault-injection test: found the opposite of the original expectation. An isolated, confirmed-`unhealthy` worker container did **not** block a dependent container declared with `--requires` against it from reaching `running` state — `service_healthy` doesn't gate start order in this sandbox's podman-compose, matching the existing `service_completed_successfully` gap. See design.md's "Verified during implementation" section and CLAUDE.md's podman-quirks section (new bullet).
- [x] 6.3 Confirmed: rebuilt all three images and brought the real stack up via `podman-compose up -d` with zero manual Rails commands; all four containers (`postgres`, `embedder`, `worker`, `web`) reached healthy unattended.
- [x] 6.4 Confirmed end-to-end: created a real `Chat`/`Message` and enqueued `ChatResponseJob` via `bin/rails runner` inside the live `web` container; the worker picked it up, called the retrieval tool, and wrote back a grounded assistant reply.
- [x] 6.5 `openspec validate rework-startup-dependencies --type change --strict` — see below.
