## Why

`chats/show.html.erb` renders every persisted `Message` row via `render message`, with no filtering. Since `ansible-retrieval-integration` registered `SearchAnsibleDocs`/`GetModuleDetails` as tools on `ChatResponseJob`, any question that triggers retrieval now persists internal orchestration messages (an assistant-with-tool-calls message, a raw tool-result message) alongside the real reply — and the unfiltered view renders all of them as full chat bubbles. To an end user this reads as the assistant briefly replying with dense, jargon-heavy raw text (tool call arguments, then a raw dump of retrieved doc chunks) before the real, correctly-worded answer appears. Confirmed live this session: asking "how can I install a brew package using ansible" reproduces it. Retrieval itself works correctly — this is purely a transcript-rendering gap that was never revisited when tools were added.

A second, related gap in the same spirit: `_citations.html.erb` auto-renders a "Sources: ..." line under every assistant reply whenever `retrieval_log` exists, with no relevance check. Today that's usually harmless because `RetrievalLog` currently only gets created when the LLM happened to call `SearchAnsibleDocs`. A separate, concurrently-explored change is expected to make `RetrievalLog` creation unconditional per assistant message (fixing a Monitoring undercount, where Grafana/`/monitoring` currently only see chat turns where retrieval happened to fire). Once that lands, this auto-rendered line would show a misleading "Sources: ansible.builtin.copy (mode, ...)" block under literally every reply, including plain chit-chat like "Hi, how are you?" — the same underlying problem this change already exists to fix: raw internal RAG machinery leaking into the visitor-facing transcript without curation.

## What Changes

- The visitor-facing chat transcript (`chats/show.html.erb`) shows only `role: user` messages and `role: assistant` messages that carry the final, real reply content — not the intermediate assistant-with-tool-calls message or `role: tool` result messages.
- Those intermediate messages remain persisted (needed for `ruby_llm`'s own conversation-replay/context-building and for future debugging/audit) — they are hidden from the rendered view, not deleted or skipped at creation.
- Resolve the mid-stream open question (see design.md): the current empty-assistant-bubble-then-live-append pattern relies on Turbo appending a message's bubble at creation time; a first-round assistant message that will later turn into a tool call cannot be known to be "hide-worthy" at creation time. design.md works out the exact mechanism (filtering, and how the initially-appended placeholder is suppressed or safely no-ops for a message that turns out to be a tool call) rather than assuming the naive `where(role: ...)` filter is sufficient.
- The "Sources: ..." line (`messages/_citations.html.erb`) becomes an opt-in "retrieval details" affordance instead of an always-rendered claim: a small button/icon on any assistant message that has a `RetrievalLog`, opening a popup with the log's raw data (retrieved chunks with their rerank scores, top module, `ansible_core_version`, cost, response time) — shown as-is, with no relevance filtering, since it's now an honest inspector rather than an implied-authoritative citation.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `chat-interface`: adds a requirement that the visitor-facing transcript excludes internal tool-orchestration messages (tool-call and tool-result messages), while `ChatResponseJob`'s tool registration and retrieval behavior (from `ansible-retrieval`) are unaffected. Also adds a requirement that retrieval source information is shown on demand rather than auto-rendered.
- `ansible-retrieval`: modifies "Retrieved sources are cited in the interface" to match — citations become available on demand rather than automatically displayed, since this change owns the mechanism that used to make them always-visible.

## Impact

- `app/views/chats/show.html.erb` — the message-rendering loop gains a filter.
- Possibly `app/models/message.rb` (a scope for "visitor-facing" messages) and/or `app/views/messages/_assistant.html.erb` / the Turbo broadcast setup, depending on how design.md resolves the mid-stream placeholder question.
- `app/views/messages/_citations.html.erb`, `app/views/messages/_assistant.html.erb` — reworked from an auto-rendered line into an on-demand popup trigger.
- A new Stimulus controller for the popup (no dialog/modal pattern exists in this app yet; native HTML `<dialog>` is the natural fit for a Rails 8 + Turbo + Tailwind stack with no new JS dependency).
- Possibly `app/helpers/messages_helper.rb` (existing `citation_groups` may move or be supplemented, depending on what the popup needs to render).
- No changes to `SearchAnsibleDocs`, `GetModuleDetails`, `RetrievalLog`, `Retrieval::*`, or `ChatResponseJob`'s tool registration/retrieval logic.
