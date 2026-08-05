## Why

`chats/show.html.erb` renders every persisted `Message` row via `render message`, with no filtering. Since `ansible-retrieval-integration` registered `SearchAnsibleDocs`/`GetModuleDetails` as tools on `ChatResponseJob`, any question that triggers retrieval now persists internal orchestration messages (an assistant-with-tool-calls message, a raw tool-result message) alongside the real reply — and the unfiltered view renders all of them as full chat bubbles. To an end user this reads as the assistant briefly replying with dense, jargon-heavy raw text (tool call arguments, then a raw dump of retrieved doc chunks) before the real, correctly-worded answer appears. Confirmed live this session: asking "how can I install a brew package using ansible" reproduces it. Retrieval itself works correctly — this is purely a transcript-rendering gap that was never revisited when tools were added.

## What Changes

- The visitor-facing chat transcript (`chats/show.html.erb`) shows only `role: user` messages and `role: assistant` messages that carry the final, real reply content — not the intermediate assistant-with-tool-calls message or `role: tool` result messages.
- Those intermediate messages remain persisted (needed for `ruby_llm`'s own conversation-replay/context-building and for future debugging/audit) — they are hidden from the rendered view, not deleted or skipped at creation.
- Resolve the mid-stream open question (see design.md): the current empty-assistant-bubble-then-live-append pattern relies on Turbo appending a message's bubble at creation time; a first-round assistant message that will later turn into a tool call cannot be known to be "hide-worthy" at creation time. design.md works out the exact mechanism (filtering, and how the initially-appended placeholder is suppressed or safely no-ops for a message that turns out to be a tool call) rather than assuming the naive `where(role: ...)` filter is sufficient.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `chat-interface`: adds a requirement that the visitor-facing transcript excludes internal tool-orchestration messages (tool-call and tool-result messages), while `ChatResponseJob`'s tool registration and retrieval behavior (from `ansible-retrieval`) are unaffected.

## Impact

- `app/views/chats/show.html.erb` — the message-rendering loop gains a filter.
- Possibly `app/models/message.rb` (a scope for "visitor-facing" messages) and/or `app/views/messages/_assistant.html.erb` / the Turbo broadcast setup, depending on how design.md resolves the mid-stream placeholder question.
- No changes to `SearchAnsibleDocs`, `GetModuleDetails`, `RetrievalLog`, `Retrieval::*`, or `ChatResponseJob`'s tool registration/retrieval logic.
