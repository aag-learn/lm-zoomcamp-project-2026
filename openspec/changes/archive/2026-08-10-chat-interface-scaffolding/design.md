## Context

`rails_app/` has no chat/LLM code yet — only the ingestion side (`AnsibleModule`, `Chunk`, `Ingestion::Chunker`, `AnsibleDocClient`, `EmbeddingClient`, `IngestAnsibleModulesJob`). `PLAN.md`'s "Agent loop" and "Persistence & UI" sections were already revised (2026-08-10) to reflect the RubyLLM decision this change implements — see that file for the full multi-provider/tool-calling/generator rationale; not re-derived here. The base gem name (`ruby_llm`, currently 1.16.0, Rails integration bundled in — no separate gem) was confirmed via `gem list -r ruby_llm` during the explore session, not assumed from docs prose.

## Goals / Non-Goals

**Goals:**
- A real person can have a persisted, multi-turn conversation with a configured LLM provider through a browser UI.
- Prove out RubyLLM + Turbo Streams + persistence in isolation, before retrieval adds its own complexity in a follow-up change.

**Non-Goals:**
- Any retrieval grounding — no tools, no citations, no `RetrievalLog`. The assistant answers only from its own trained knowledge in this change; that's expected, not a defect to fix here.
- Renaming RubyLLM's generated `Chat`/`Message`/`ToolCall`/`Model` — kept as the gem's own defaults (see Decisions).
- Multi-provider support — configuring OpenAI now doesn't preclude Anthropic/etc. later, but wiring more than one provider isn't done in this change.

## Decisions

**Keep RubyLLM's default model/table names** (`Chat`, `Message`, `ToolCall`, `Model`), don't rename via the generator's `chat:Conversation` syntax. Easier to match against the gem's own docs and community examples when something breaks, and avoids carrying a permanent naming divergence from every RubyLLM example anyone will find while debugging this.

**`Feedback` belongs to `Message`, not a conversation-level model.** A rating is about one specific reply; multi-turn conversations can have several assistant replies, each independently ratable. `belongs_to :message`, `rating` (+1/-1) — a new, small, project-specific model, not something RubyLLM generates.

**API key via `ENV.fetch("OPENAI_API_KEY")`, no default** — confirmed RubyLLM's `config.openai_api_key = <anything>` in `config/initializers/ruby_llm.rb` is a plain Ruby assignment, not hardwired to `Rails.application.credentials` despite the gem's own docs suggesting that pattern. `ENV.fetch` with no default matches the existing no-default pattern for real secrets (`RAILS_MASTER_KEY`, `POSTGRES_PASSWORD`), not the `ENV.fetch`-with-default pattern used for the throwaway local dev-database password in `rails-dev-database-defaults` — this is a real, paid, provider secret.

**Multi-turn is the default, not single-shot** — a `Chat` can hold more than one exchange, and prior messages are included as context for later replies, simply by using RubyLLM's `Chat`/`Message` as designed rather than forcing one-exchange-per-`Chat`. No extra code needed to support this; it would take *extra* code to prevent it, which this change doesn't do.

**Tests stub the LLM provider**, matching the project's established testing convention (`CLAUDE.md`) — a chat-flow test that actually calls a real provider would be slow, flaky, cost money, and require a real API key in CI. Uses `webmock` (already in the `:test` group from `ansible-ingestion-pipeline`) to stub the provider's HTTP endpoint, the same approach already used for `EmbeddingClient`'s tests.

**`OPENAI_API_KEY` is required by both `web` and `worker`, not just `web`** — discovered mid-implementation, corrected in proposal.md's Impact section (see that file for the full reasoning). The `ruby_llm:chat_ui` generator's `ChatResponseJob` runs via `ActiveJob.perform_later`, and `web`'s `RAILS_ENV=production` sets `queue_adapter = :solid_queue` — meaning `web` only enqueues the job, `worker`'s `bin/jobs` process is what actually executes it (and therefore what actually needs to reach the LLM provider). `worker` still serves no HTTP chat traffic; it just also runs this one more kind of background job now, alongside `IngestAnsibleModulesJob`.

## Risks / Trade-offs

- **RubyLLM's generated chat UI views may not match this project's existing layout/styling.** → Acceptable for this change; visual polish is not a rubric requirement, functional correctness is. Revisit only if it's actually broken, not just plain.
- **Multi-turn context sent to the provider grows with conversation length, with no truncation/summarization.** → Not a problem at this project's expected scale (a handful of manual/eval exchanges), so not addressed here — worth revisiting only if it becomes a real cost/context-window issue later.
- **`Message` cannot have a `validates :content, presence: true`** (RubyLLM's own documented constraint — it persists an empty assistant message during streaming before content arrives). → Accepted as a known RubyLLM behavior, not a bug in this change; don't add that validation.
- **`curl`-based verification can pass while real-browser behavior fails.** Realized concretely, not hypothetically: `assume_ssl`/`force_ssl` (Rails 8's Kamal-oriented generated defaults, present since `rails-app-scaffold`) broke every real-browser form submission with a 422 — invisible to curl-based checks because curl doesn't send an `Origin` header on POST by default, and CSRF's origin-match check only activates when one is present. → Fixed (see proposal.md's third correction); worth remembering for future changes with interactive forms — a curl-clean verification isn't the same guarantee as a real-browser one specifically for CSRF/origin-dependent behavior.

## Migration Plan

1. Add `gem "ruby_llm"` to `rails_app/Gemfile`, `bundle install`.
2. `bin/rails generate ruby_llm:install` → `Chat`/`Message`/`ToolCall`/`Model` migrations + models, initializer stub.
3. Edit the generated `config/initializers/ruby_llm.rb` to read `ENV.fetch("OPENAI_API_KEY")`.
4. `bin/rails generate ruby_llm:chat_ui` → controllers/views/routes.
5. Add `Feedback` migration + model by hand (not RubyLLM-generated).
6. Add `OPENAI_API_KEY` to `.env.example`/`.env`; add the required-var entry to `web`'s block in `docker-compose.yml`.
7. Run migrations, smoke-test locally before containerizing.
8. No rollback complexity beyond standard migration rollback — additive only, nothing existing is altered.

## Open Questions

- **Exact shape of the `ruby_llm:chat_ui` generator's output** (file names, whether it assumes a specific Rails version's Hotwire setup) — not yet inspected directly; first implementation task should run the generator and read what it actually produces before writing further tasks that assume specific file paths. Doesn't change the spec or this change's scope, only the task breakdown's level of detail once the generator's real output is known.
