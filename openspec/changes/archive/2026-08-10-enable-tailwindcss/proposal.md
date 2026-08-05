## Why

`chat-interface-scaffolding` shipped RubyLLM's generated chat UI as-is — plain HTML with inline `style="..."` attributes on every element, no CSS framework. `PLAN.md`'s original repo-setup notes assumed `rails new --css=tailwind`, but the actual scaffold never installed it (confirmed empirically — no `tailwindcss-rails`/`cssbundling-rails` gem in the Gemfile). This change installs Tailwind and restyles the existing chat views to use it, so the Interface rubric category isn't resting on unstyled scaffold output.

## What Changes

- Add the `tailwindcss-rails` gem (confirmed via `gem list -r tailwindcss` — the official Rails-maintained option; ships a standalone Tailwind CLI binary via `tailwindcss-ruby`, no Node.js/`package.json` needed, consistent with this project already using `importmap-rails` for JS with zero Node toolchain).
- Run `bin/rails tailwindcss:install` to scaffold the Tailwind source/build pipeline and wire it into the asset pipeline (Propshaft) and `bin/dev`.
- Replace inline `style="..."` attributes with Tailwind utility classes across the chat-facing views: `app/views/chats/*.erb`, `app/views/messages/*.erb` (including the hand-written `_feedback.html.erb` from `chat-interface-scaffolding`). `app/views/models/*.erb` (RubyLLM's auto-generated model-browsing admin page, not user-facing chat UI) is out of scope — lower priority, not a rubric-relevant surface.
- Verify the `web` image's existing `assets:precompile` Dockerfile step (added in `chat-interface-scaffolding`) picks up the Tailwind build automatically, since `tailwindcss-rails` hooks itself into that same Rake task — not assumed, checked directly once installed.

**Scope added after initial completion**: reviewing the restyled UI surfaced a real gap — the layout has no persistent navigation at all. Every page relies on scattered, inconsistent links, and worst of all, `chats/show` and `chats/new` have no way to reach Models at all short of manually editing the URL. Folded into this change (not split out) since it's a direct continuation of making the chat UI's presentation coherent, the same theme as the rest of this change: add a persistent nav bar (Chats / Models / New chat, current-section highlighted) to the shared layout, reachable from every page.

**Scope added again after that**: with the nav bar in place, `models/index.html.erb`'s leftover in-page `<%= link_to "Chats", chats_path %>` now reads as a second, confusing, unstyled menu duplicating the real nav — this reverses this change's original decision to leave `models/*.erb` unstyled. Restyling it now (removing the redundant link, styling the "Refresh Models" button and table) rather than leaving a genuinely confusing UI in place. Also setting a real default chat model: `config.default_model` was never actually configured (commented out in the initializer since `chat-interface-scaffolding`), silently falling back to RubyLLM's own gem-level default (`gpt-5.4`, confirmed directly via `RubyLLM.config.default_model`, not assumed) — setting it explicitly to `gpt-5-mini` (confirmed as a real `provider: "openai"` model ID in the loaded registry — distinct from an OpenRouter-routed `openai/gpt-5-mini` entry that also exists but isn't reachable with only `openai_api_key` configured). This is a genuine behavior change, not styling — worth being explicit about even though it doesn't touch the `chat-interface` spec's wording (which never pinned down a specific default model).

**Scope added a third time**: reported flash messages appearing on the left of the page instead of under the nav bar. Root cause: `<main>`'s `flex` (row) class plus each view rendering its own flash `<p>` *outside* that page's centered content wrapper — a layout bug, not a color/spacing polish issue, introduced by this change's own restyling pass (the original inline-styled views didn't have this problem, since they had no flex layout at all). Fixed by consolidating the 3 duplicated per-view flash blocks into the shared layout, rendered once directly under the nav.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none — this only changes how the existing `chat-interface` capability's UI is styled, not any of its specified behavior: sending/receiving messages, persistence, streaming, multi-turn context, feedback, and credential handling all work identically. `skip_specs: true` set in `.openspec.yaml` accordingly.)

## Impact

- **New**: `app/assets/tailwind/application.css` (or equivalent — exact generator output verified during design/implementation, not assumed), Tailwind's build config.
- **Modified**: `rails_app/Gemfile`/`Gemfile.lock` (new gem), `app/views/layouts/application.html.erb` (stylesheet tag, persistent nav bar), `app/helpers/application_helper.rb` (active-section highlighting helper), `app/views/chats/*.erb`, `app/views/messages/*.erb`, `app/views/models/*.erb` (restyled, redundant in-page nav link removed), `config/initializers/ruby_llm.rb` (`config.default_model = "gpt-5-mini"`), `bin/dev`/`Procfile.dev` (Tailwind watch process for local dev).
- **No changes to**: any controller, model, job, route, or the `chat-interface` capability's specified requirements — the default-model change is a real behavior tweak (see above) but not one the spec pinned to a value.
