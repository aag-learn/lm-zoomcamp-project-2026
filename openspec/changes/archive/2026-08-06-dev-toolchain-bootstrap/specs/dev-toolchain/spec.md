## ADDED Requirements

### Requirement: Project-managed tools declared in mise
The system SHALL declare `uv` and `python` in `mise.toml`'s `[tools]` table, so `mise install`/`mise bootstrap` provisions both without any manual installation step.

#### Scenario: Tools install via mise
- **WHEN** a contributor with `mise` installed runs `mise install` (or `mise bootstrap`) from the repo root
- **THEN** `uv` and `python` are both installed and available on `PATH` within the `mise`-managed environment

### Requirement: System packages declared as mise bootstrap packages for both apt and brew
The system SHALL declare `curl` and `jq` in `mise.toml`'s `[bootstrap.packages]` table via both the `apt:` and `brew:` managers, so `mise bootstrap` can install both as system packages on either a Debian/Ubuntu-based Linux machine or a Mac.

#### Scenario: Packages install via mise bootstrap on Linux
- **WHEN** a contributor on a Debian/Ubuntu-based machine, with `system_packages.managers` restricted to `["apt"]`, runs `mise bootstrap` from the repo root
- **THEN** `curl` and `jq` are installed via `apt` and available on `PATH`, and the `brew:` entries are reported as skipped, not attempted

#### Scenario: Packages install via mise bootstrap on macOS
- **WHEN** a contributor on a Mac, with `system_packages.managers` restricted to `["brew"]`, runs `mise bootstrap` from the repo root
- **THEN** `curl` and `jq` are installed via `brew` and available on `PATH`, and the `apt:` entries are reported as skipped, not attempted

### Requirement: Per-machine package manager restriction via a gitignored local override
The system SHALL document, and rely on, a gitignored `mise.local.toml` file in which each contributor sets `system_packages.managers` to restrict `mise bootstrap` to only their machine's package manager, preventing an unwanted attempt to install a different platform's package manager (e.g. bootstrapping Homebrew on Linux to satisfy `brew:` entries).

#### Scenario: mise.local.toml is not committed
- **WHEN** `git status` is run after a contributor creates their own `mise.local.toml`
- **THEN** `mise.local.toml` does not appear as a trackable/untracked file, because it is listed in `.gitignore`

#### Scenario: Without the restriction, the other platform's manager is not silently skipped
- **WHEN** both `apt:` and `brew:` entries exist in `[bootstrap.packages]` and no `system_packages.managers` restriction is set
- **THEN** `mise bootstrap` on Linux attempts to install Homebrew itself to satisfy the `brew:` entries, rather than skipping them — documented as the reason the restriction is required, not optional

### Requirement: README documents the Development setup command
The system SHALL provide a `README.md` at the repo root containing a **Development** section that assumes `mise` is already installed, links to the official mise installation documentation, documents creating a per-machine `mise.local.toml`, and states the command needed to provision every project-declared tool and package.

#### Scenario: Following the README from a fresh clone
- **WHEN** a contributor with `mise` already installed reads the README's Development section
- **THEN** they find a link to mise's installation docs, instructions for creating `mise.local.toml` with the correct `system_packages.managers` value for their OS, and the command (`mise bootstrap`) to run to provision `uv`, `python`, `curl`, and `jq`

#### Scenario: README has no other sections yet
- **WHEN** `README.md` is inspected
- **THEN** it contains exactly one section, Development, and no other top-level sections
