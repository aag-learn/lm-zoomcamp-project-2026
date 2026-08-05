## Context

See proposal.md for the bug and its root cause. Two facts drive this design, both verified directly against the installed `ruby_llm` gem source and the running app this session:

1. **Rendering dispatch is uniform across both code paths.** Both the initial full-page load (`chats/show.html.erb`'s `render message` loop) and every live Turbo broadcast (`Message.broadcasts_to`'s `after_create_commit`/`after_update_commit`, from the gem's `acts_as_message`) resolve the same way: via `Message#to_partial_path`, to one of `messages/{user,assistant,tool_calls,tool,system}`. There is exactly one place that decides what a message "looks like" — the partial file for its resolved path.
2. **A single conversational turn that uses a tool spans 3+ `Message` rows**, created via two different mechanisms:
   - The assistant-with-tool-calls message and the final assistant message are each created empty (`before_message` → `persist_new_message`, `content: ''`) *before* their completion round starts, then updated in place once the round finishes (`after_message` → `persist_message_completion`). The empty-then-filled-in lifecycle is what makes real-time streaming work today (`_assistant.html.erb`'s content div is what `ChatResponseJob#perform`'s block appends chunks into) — and it's also why an assistant message's rendered partial can visibly switch mid-turn: it starts with no `tool_calls`, so it's created as `messages/assistant`, then gets `tool_calls` attached and re-broadcasts as `messages/tool_calls`.
   - The tool-result message is created once, already carrying its full content (`add_tool_result_message` → a single `create!`) — no empty-then-filled lifecycle.

## Goals / Non-Goals

**Goals:**
- Fix both the live-streaming flash (the actual reported symptom) and the post-reload transcript in one mechanism, not two separately-maintained filters.
- Leave `ruby_llm`'s persistence callbacks, `ChatResponseJob`, and the retrieval/tool code entirely untouched — this is a rendering-only fix.

**Non-Goals:**
- Eliminating the brief empty-bubble flash that still occurs for a tool-call round's first message before it resolves into a (now-invisible) tool-call state — see Risks/Trade-offs.
- Any visible "the assistant is looking things up..." loading affordance during a tool-call round — worth considering later, not part of fixing this bug.

## Decisions

**Make `messages/_tool_calls.html.erb` and `messages/_tool.html.erb` render nothing, instead of filtering in `chats/show.html.erb`.**

Both files become intentionally-empty partials (an ERB comment explaining why, no markup):
```erb
<%# Intentionally blank: tool-call/tool-result messages are internal orchestration,
    never shown in the visitor-facing transcript. See hide-tool-orchestration-messages. %>
```

Because `to_partial_path` is what both the initial page load *and* every Turbo broadcast route through, this single change point fixes both the live flash and the reload case — no separate `where(role: ...)` filter needed in the controller/view, which would only fix the reload case (Turbo's model-level broadcast callbacks fire independent of what the view's query looks like, so a view-only filter would leave the live-streaming flash completely unfixed). Confirmed by tracing through the gem's callback wiring: `after_create_commit`/`after_update_commit` broadcast unconditionally, using `to_partial_path` at broadcast time — the only lever available without touching the gem's internals is the partial content itself.

**Delete the now-dead code**: `app/views/messages/tool_calls/_default.html.erb`, `app/views/messages/tool_results/_default.html.erb`, and `MessagesHelper#tool_call_partial`/`#tool_result_partial`/`#partial_for` (verified: only called from the two partials being blanked, no other callers). Per this project's convention, unused code gets deleted, not left as orphaned dead weight.

**Walking through both message lifecycles under this fix, to confirm no new visual artifact beyond the accepted flash (see Risks):**
- *Tool-result message* (single `create!`, full content from the start): its one and only broadcast is an append of empty content — no DOM element for it is ever created. Fully invisible, no flash.
- *Assistant-with-tool-calls message* (empty create, later updated): created as `messages/assistant` (unchanged, not blanked) → appends a normal-looking, momentarily-empty assistant bubble (this is the accepted flash, see below) → once `tool_calls` are attached, re-broadcasts as `messages/tool_calls`, now blank → Turbo's `replace` action swaps the existing `<div id="message_X">` element for nothing, removing it from the DOM entirely. No leftover empty wrapper.
- *Final assistant message* (empty create, streamed, then finalized): entirely unaffected — this is exactly today's working streaming behavior (`messages/assistant`, never touched by this change).
- *A turn that never calls a tool*: entirely unaffected — same single assistant message lifecycle as always.

## Risks / Trade-offs

- **A brief empty assistant bubble still appears and disappears for a tool-call round.** The assistant-with-tool-calls message is created (and broadcast-appended) before it's known whether the round will end in a tool call or real content — that decision isn't made until the round finishes, so there's no way to withhold the initial append without conditionally suppressing `Message.broadcasts_to`'s create-broadcast (i.e., reaching into how/when the gem's persistence callbacks fire). Considered and rejected: it would require making `ChatResponseJob` (or a `Message` callback condition) aware of streaming state that the gem doesn't expose cleanly, for a fix whose only benefit is removing a sub-second blank bubble — not worth the added coupling to gem internals for this change. → Accepted: an empty, textless bubble that appears then cleanly vanishes is a minor, forgivable artifact, categorically different from the current bug (dense unreadable raw text that lingers as a permanent, separate chat entry).
- **Blanking a partial file (rather than filtering a query) is a slightly unusual Rails idiom** — a reader unfamiliar with `to_partial_path` dispatch could mistake the empty files for an oversight. → Mitigated with an explanatory comment in both files, and this design doc.

**The retrieval-details popup uses a native HTML `<dialog>` element plus a small Stimulus controller, not a new JS library.** Checked: this app has no existing modal/dialog pattern (`grep -rl "dialog\|modal\|popup" app/views app/javascript` returns nothing beyond the Rails-scaffold `hello_controller.js`). `<dialog>` + `.showModal()` needs no dependency beyond what a Rails 8 + Turbo + Tailwind stack already ships, and is a one-file Stimulus controller (open/close), consistent with this project's "don't add a library for what the platform already provides" pattern elsewhere (e.g. Ruby's own `net/http` for the `web` healthcheck).

**The popup shows `RetrievalLog`'s raw data unfiltered — no relevance/confidence logic, anywhere.** This was a deliberate decision made while exploring the companion change (unconditional `RetrievalLog` logging): rather than needing a calibrated confidence threshold to decide whether a citation is "real enough" to show (which turned out not to have a clean cutoff — compositional/imperative phrasing like "create a task to copy a file..." scored lower on the reranker than simple factual questions, despite being equally genuine), making display opt-in removes the need for that judgment entirely. The popup isn't claiming "these are the sources," it's answering "what did the system actually look up" — true regardless of relevance.

**Kept the existing `if assistant.retrieval_log` nil-guard**, so the popup trigger only appears when a `RetrievalLog` actually exists. This makes the two changes' landing order irrelevant: if this change lands first, behavior is unchanged from today (button only on tool-triggered replies); if the companion change lands first, every reply gets a button. Neither ordering requires touching this change's logic.

**Discovered during implementation (2.2): `app/views/messages/_system.html.erb` also needs blanking.** This design was written before the companion `guarantee-retrieval-grounding` change existed, so it only accounted for `tool_calls`/`tool` role messages. That change (already merged) makes `ChatResponseJob` call `chat.with_instructions(SYSTEM_INSTRUCTIONS)` on every turn, which persists a `role: "system"` `Message` — and `to_partial_path`'s dispatch (`role.to_s.presence || 'assistant'` for anything that isn't a tool-call or `role: "tool"`) resolves that to `messages/system`, which renders a full visible "System" bubble containing the raw instructions text. Confirmed live: a fresh `Chat` with `with_instructions` called shows `[[id, "system", "messages/system"]]` in its message list. This means **every real chat, right now, shows the raw system prompt as a visible chat bubble** — the exact category of bug this change exists to fix (internal orchestration/config data leaking into the visitor-facing transcript), just via a message role this design didn't originally know would exist. Fixed the same way as `tool_calls`/`tool`: blank `_system.html.erb` too, via the same `to_partial_path`-dispatch mechanism already chosen — no new design decision needed, same rationale applies unchanged (see the "Make `messages/_tool_calls.html.erb`..." decision above).
