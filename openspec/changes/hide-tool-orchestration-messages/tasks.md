## 1. Tests first

- [ ] 1.1 Write a test asserting `render` on a `role: "tool"` message and on an assistant message with `tool_calls` attached both produce blank/empty output — seed the minimal records needed (a tool-call message with an associated `ToolCall`, a `role: "tool"` result message), render each via the real partial dispatch (`ActionView::TestCase` or equivalent), assert the rendered output is empty (or contains none of the raw tool name / raw content that would appear today)
- [ ] 1.2 Write an integration test (extending `ChatsControllerTest`'s existing pattern) that seeds a full tool-using turn — user message, assistant-with-tool-calls message + its `ToolCall`, a `role: "tool"` result message with distinctive raw content, and a final assistant message with distinctive real-answer content — `GET` the chat page, and assert the response body includes the user message and the final assistant content, but does NOT include the tool call's raw arguments text or the tool result's raw content text
- [ ] 1.3 Confirm both new tests fail against the current (unfixed) partials, for the expected reason (today's partials render the raw content, not blank)

## 2. Implement

- [ ] 2.1 Replace the contents of `app/views/messages/_tool_calls.html.erb` and `app/views/messages/_tool.html.erb` with an explanatory ERB comment only (no markup) — per design.md, this is the single change point that fixes both live-streaming broadcast and full-page-reload rendering, since both route through `Message#to_partial_path`
- [ ] 2.2 Delete the now-unreachable `app/views/messages/tool_calls/_default.html.erb` and `app/views/messages/tool_results/_default.html.erb`
- [ ] 2.3 Delete the now-unreachable `MessagesHelper#tool_call_partial`, `#tool_result_partial`, and `#partial_for` (confirmed during design: no other callers)
- [ ] 2.4 Run the tests from section 1, confirm they now pass

## 3. Verification

- [ ] 3.1 Run the full test suite, rubocop, and brakeman
- [ ] 3.2 Rebuild the `web`/`worker` images, bring up the stack, and replay this session's exact repro (asking a question that triggers `SearchAnsibleDocs`, e.g. "how can I install a brew package using ansible") through the real running app; confirm the transcript shows only the user's message and the final assistant reply (with citation) — no raw tool-call or tool-result bubble at any point during streaming, and the same after a page reload
- [ ] 3.3 Confirm a plain question that doesn't trigger any tool still streams and renders exactly as before (no regression for the non-tool path)
