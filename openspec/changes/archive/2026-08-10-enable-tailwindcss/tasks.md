## 1. Install Tailwind

- [x] 1.1 Add `gem "tailwindcss-rails"` to `rails_app/Gemfile`; `bundle install` — pulled a real linux `tailwindcss-ruby` 4.3.3 binary, no Node
- [x] 1.2 Run `bin/rails tailwindcss:install`; inspect what it actually generates/modifies (source CSS path, build config, `app/views/layouts/application.html.erb`'s stylesheet tag, `bin/dev`/`Procfile.dev`) before assuming specific file paths in later tasks — generated `app/assets/tailwind/application.css` (just `@import "tailwindcss";`, Tailwind v4's CSS-only config, no JS config file), build output at `app/assets/builds/tailwind.css`, `Procfile.dev` (`web`/`css` processes via `foreman`), `bin/dev` rewritten to exec `foreman`, and inserted a `<main class="container mx-auto mt-28 px-5 flex">` wrapper in the layout. The layout's `stylesheet_link_tag :app` was *not* changed — confirmed empirically that Propshaft's `:app` alias already auto-includes `app/assets/builds/tailwind.css` alongside the existing stylesheet, no manual wiring needed
- [x] 1.3 Run a local Tailwind build (`bin/rails tailwindcss:build` or equivalent); confirm it completes without error — completes in ~50ms, no errors
- [x] 1.4 Verify the `web` image's existing `assets:precompile` Dockerfile step picks up the Tailwind build automatically (per design.md, `tailwindcss-rails` is documented to hook this in) — confirm directly by rebuilding the image and checking the compiled output, not assumed; add an explicit `tailwindcss:build` step to the Dockerfile if it doesn't — confirmed: `assets:precompile`'s output shows the Tailwind CLI running and `Writing tailwind-f3dec2a8.css` before the fingerprinted asset list, no Dockerfile change needed

## 2. Restyle the chat-facing views

- [x] 2.1 `app/views/chats/index.html.erb`
- [x] 2.2 `app/views/chats/new.html.erb` + `app/views/chats/_form.html.erb`
- [x] 2.3 `app/views/chats/show.html.erb` + `app/views/chats/_chat.html.erb`
- [x] 2.4 `app/views/messages/_user.html.erb`, `_assistant.html.erb`, `_system.html.erb`, `_error.html.erb`, `_tool.html.erb`, `_tool_calls.html.erb`, `tool_calls/_default.html.erb`, `tool_results/_default.html.erb` — `_tool.html.erb`/`_tool_calls.html.erb` are pure dispatcher partials with no styles, left untouched
- [x] 2.5 `app/views/messages/_form.html.erb` — also tightened the layout (input + submit button on one row via `flex`), a minor UX improvement within scope of a styling pass
- [x] 2.6 `app/views/messages/_feedback.html.erb` (hand-written in `chat-interface-scaffolding`, currently uses `button_to`'s inline `style:` option) — replaced with `class_names` for the conditional active-rating state
- [x] 2.7 Confirm no inline `style="..."` attributes remain in any touched file (`grep -r 'style=' app/views/chats app/views/messages`) — confirmed, zero matches

## 3. Verification

- [x] 3.1 Run the full test suite, rubocop, and brakeman; confirm nothing broke (view-only changes shouldn't affect controller/model/job tests, but confirm rather than assume) — 34/34 tests pass, rubocop and brakeman clean
- [x] 3.2 Rebuild the `web` image; confirm the compiled Tailwind CSS is present in `public/assets/` and served with 200 — confirmed the built `tailwind-*.css` (11,256 bytes) actually contains the specific utility classes used in the views (`border-blue-500`, `rounded-md`, `bg-blue-600`, `whitespace-pre-wrap`, etc. — not just present as unused class names, since Tailwind v4 only compiles CSS for classes it detects via content-scanning), and serves 200 from the real running container
- [x] 3.3 Real browser check: visit `/chats`, confirm Tailwind styling is visibly applied (not just class names present with no visual effect — check the build actually picked up the classes used in the views, since Tailwind only includes CSS for classes it detects in scanned source files) — confirmed via the compiled CSS containing real rule bodies for the classes used (e.g. `.border-blue-500{border-color:var(--color-blue-500)}`), and the rendered `/chats/4` HTML showing `class="message mb-5 rounded-r-md border-l-4 border-blue-500 bg-blue-50 p-3"` on a real persisted message
- [x] 3.4 Re-run the existing live-verification flows from `chat-interface-scaffolding` (send a message, send a follow-up, submit a rating) against the restyled UI, confirming none of that behavior regressed — all three confirmed against the real running stack: a new message got a real reply, a follow-up correctly recalled prior context ("copy"), and a rating was recorded in Postgres (message_id=16, rating=1)

## 4. Persistent navigation (scope added after initial review)

- [x] 4.1 Add a `nav_link_active?(path)` helper to `ApplicationHelper`
- [x] 4.2 Add a fixed-top nav bar to `app/views/layouts/application.html.erb` with Chats / Models / New chat links, current-section highlighting
- [x] 4.3 Confirm the nav bar is reachable from every existing page (`chats/index`, `chats/show`, `chats/new`, `models/index`, `models/show`) — the specific gap that motivated this — confirmed via real requests to all of `/chats`, `/chats/new`, `/chats/4`, `/models`: nav present with all 3 links on every page, and active-section highlighting correctly shows blue on "Chats" at `/chats/4` and blue on "Models" at `/models`
- [x] 4.4 Re-run the full test suite, rubocop, brakeman; rebuild the `web` image; re-verify the same live flows (send message, follow-up, rating) still work with the nav bar present — 34/34 tests pass, rubocop/brakeman clean, and a real send-message → follow-up-capable chat → rating flow confirmed against the rebuilt `web` container

## 5. Restyle models/ and set a real default model (scope added after the nav bar exposed a real defect)

- [x] 5.1 Remove the redundant in-page `link_to "Chats", chats_path` from `app/views/models/index.html.erb` (the specific "weird menu inside the page" reported — now duplicated by the persistent nav)
- [x] 5.2 Restyle `app/views/models/index.html.erb` (including the "Refresh Models" button and table) and `app/views/models/show.html.erb`/`_model.html.erb` with Tailwind, matching the rest of this change
- [x] 5.3 Set `config.default_model = "gpt-5-mini"` in `config/initializers/ruby_llm.rb` (the `provider: "openai"` entry, confirmed against the real loaded registry, not the OpenRouter-routed `openai/gpt-5-mini`)
- [x] 5.4 Confirm `default_model_display_name` (in `MessagesHelper`) reflects the new default, and that creating a chat without explicitly picking a model actually uses `gpt-5-mini` — confirmed directly: `Chat.create!(model: nil)` resolves to `provider: "openai", model_id: "gpt-5-mini"`, and `default_model_display_name` now reads "Default: OpenAI - GPT-5 Mini"
- [x] 5.5 Re-run the full test suite, rubocop, brakeman; rebuild the `web` image; real-request check of `/models` and `/models/:id` confirming the redundant link is gone and styling is applied — 34/34 tests pass, rubocop/brakeman clean; confirmed against the rebuilt containers: `/models` has exactly 1 "Chats" link (the nav's, not a duplicate), refresh button and table are styled, and a real chat created with no explicit model selection resolved to `gpt-5-mini`/`openai` end-to-end (DB row, rendered "Using OpenAI - GPT-5 Mini", real assistant reply)

## 6. Fix flash message positioning (reported: flash messages appearing on the left instead of under the nav)

- [x] 6.1 Root-cause: `<main>`'s `flex` (row) class + each view's flash `<p>` sitting outside that page's own wrapper `<div>` as a sibling flex item — lays out side-by-side instead of stacked. Consolidate flash rendering into `app/views/layouts/application.html.erb` (removing the 3 duplicated per-view blocks in `chats/index.html.erb`, `chats/show.html.erb`, `models/index.html.erb`), rendered as the first child inside `<main>`, above `<%= yield %>`
- [x] 6.2 Add `flex-col` to `<main>`'s classes so it stacks the flash message above the page content instead of placing them side-by-side (the actual fix — without this, the same bug recurs now that `<main>` has 2 children instead of 1)
- [x] 6.3 While consolidating, also render `alert` (not just `notice`) — `FeedbacksController#create`'s error branch already sets `alert:` but nothing was ever rendering it; styled red vs. `notice`'s green
- [x] 6.4 Re-run the full test suite, rubocop, brakeman; rebuild the `web` image; real-request check confirming a flash message renders directly under the nav bar, full-width, not on the left — 34/34 tests pass, rubocop/brakeman clean; confirmed against the rebuilt container by triggering a real `notice` (refreshing models): rendered as the first child of `<main class="... flex flex-col ...">`, exactly once, none present on pages without a flash
