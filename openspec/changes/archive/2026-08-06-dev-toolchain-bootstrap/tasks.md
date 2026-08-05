## 1. mise.toml tools

- [x] 1.1 Add `"uv" = "latest"` and `"python" = "latest"` to `mise.toml`'s `[tools]` table
- [x] 1.2 Run `mise install` and confirm `uv` and `python` are installed and on `PATH`

## 2. mise.toml bootstrap packages

- [x] 2.1 Add `[bootstrap.packages]` table to `mise.toml` with `"apt:curl"`, `"apt:jq"`, `"brew:curl"`, `"brew:jq"`, all `"latest"` (e.g. via `mise bootstrap packages use apt:curl apt:jq brew:curl brew:jq`)

## 3. Local per-machine override

- [x] 3.1 Add `mise.local.toml` to `.gitignore`
- [x] 3.2 On this (Linux) machine, create `mise.local.toml` with `[settings]` / `system_packages.managers = ["apt"]`
- [x] 3.3 Run `mise bootstrap packages status` and confirm `apt:curl`/`apt:jq` show installed and `brew:curl`/`brew:jq` show `skipped (excluded by the system_packages.managers setting)` — not `missing`, not attempting a Homebrew bootstrap
- [x] 3.4 Run `mise bootstrap` and confirm `curl` and `jq` are installed and on `PATH`

## 4. README

- [x] 4.1 Create `README.md` at the repo root with a single `## Development` section
- [x] 4.2 Development section: note that `mise` must already be installed, with a link to `https://mise.jdx.dev/installing-mise.html`
- [x] 4.3 Development section: document creating a per-machine `mise.local.toml` with `system_packages.managers = ["apt"]` (Linux) or `["brew"]` (macOS), and explain why it's required (avoids `mise` attempting to bootstrap the other platform's package manager)
- [x] 4.4 Development section: document `mise bootstrap` as the command that provisions every project-declared tool/package

## 5. Verification

- [x] 5.1 Temporarily remove `mise.local.toml` and confirm (via `mise bootstrap packages status` or a dry-run) that `brew:` entries would otherwise be attempted rather than skipped on this Linux machine — reproduces the exact risk the README step exists to prevent, then restore `mise.local.toml`
- [x] 5.2 From a shell without `uv`/`python`/`curl`/`jq` on `PATH` (or after `mise bootstrap packages prune` + `mise uninstall uv python`), run `mise bootstrap` and confirm all four become available — verified via `mise exec` resolving all four after `mise bootstrap`; skipped the destructive prune/uninstall round-trip since `apt:curl`/`apt:jq` are real system packages other tools on this shared machine may depend on
- [x] 5.3 Confirm `mise.toml`'s existing `claude`/`openspec` entries are unchanged
- [x] 5.4 Confirm `README.md` contains exactly one top-level section (Development) and the mise install link resolves
- [x] 5.5 Confirm `git status` does not show `mise.local.toml` as trackable/untracked
