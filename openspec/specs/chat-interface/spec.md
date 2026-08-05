## Purpose

Give visitors a persisted, multi-turn chat interface backed by a configured LLM provider, with per-reply feedback — the web-facing plumbing the rest of the app's RAG capabilities will be layered onto in a later change.

## Requirements

### Requirement: Visitor can send a message and receive an assistant reply
The system SHALL allow a visitor to submit a text message through the chat interface and receive a generated reply from a configured LLM provider, without a full page reload.

#### Scenario: Submitting a message returns a reply
- **WHEN** a visitor submits a text message via the chat interface
- **THEN** an assistant reply is generated and displayed in the same page, without a full page reload

### Requirement: Conversation history persists
The system SHALL persist every message in a conversation — both visitor and assistant — so the conversation remains available after a page reload.

#### Scenario: Reloading the page preserves message history
- **WHEN** a visitor sends one or more messages, then reloads the page
- **THEN** all previously sent and received messages in that conversation are still displayed

### Requirement: Assistant replies stream incrementally
The system SHALL display an assistant reply incrementally as it is generated, rather than only once the full response is complete.

#### Scenario: Partial reply is visible before the response finishes
- **WHEN** an assistant reply is being generated
- **THEN** partial content is visible in the browser before the full reply has finished generating

### Requirement: A conversation supports multiple, context-aware turns
The system SHALL allow a visitor to send more than one message within the same conversation, and SHALL include the conversation's prior messages as context when generating each new reply.

#### Scenario: A follow-up message is sent within the same conversation
- **WHEN** a visitor sends a second message in a conversation that already has a prior exchange
- **THEN** the new message is added to the same conversation, not a new one, and prior messages in that conversation are included as context for the generated reply

### Requirement: Assistant replies can be rated
The system SHALL allow a visitor to submit a positive or negative rating for a specific assistant reply.

#### Scenario: Submitting a rating on a reply
- **WHEN** a visitor submits a positive or negative rating on an assistant reply
- **THEN** the rating is recorded and associated with that specific reply

#### Scenario: Multiple replies in one conversation are rated independently
- **WHEN** a conversation contains more than one assistant reply
- **THEN** each reply can be rated independently of the others

### Requirement: LLM provider credentials are configured via environment variables
The system SHALL source the LLM provider's API key from an environment variable, not from Rails' encrypted credentials store, and SHALL fail clearly rather than silently if the variable is not set.

#### Scenario: Missing API key fails clearly
- **WHEN** the application is started without the required LLM provider API key environment variable set
- **THEN** it fails clearly (at startup or at the point a chat request is made), rather than silently proceeding with no key or an empty one

#### Scenario: Required variable is documented
- **WHEN** a contributor inspects `.env.example`
- **THEN** they find the LLM provider API key variable listed with a placeholder value

### Requirement: Visitor-facing transcript excludes internal tool-orchestration messages
The system SHALL display, in the chat transcript, only the visitor's own messages and the assistant's final reply content — and SHALL NOT display raw tool-call invocations, raw tool-result content, or system/instruction messages as chat bubbles, even though those messages are persisted internally.

#### Scenario: A reply that uses a tool shows only the final answer
- **WHEN** an assistant reply is generated using one or more tool calls
- **THEN** the transcript displays the visitor's message and the assistant's final reply content, and does not display the tool-call invocation or the tool's raw result as a separate chat entry

#### Scenario: A reply that doesn't use a tool is unaffected
- **WHEN** an assistant reply is generated without any tool calls
- **THEN** the transcript displays it exactly as before, with no change in behavior

#### Scenario: Reloading the page still hides orchestration messages
- **WHEN** a visitor reloads a conversation that included a tool-using reply
- **THEN** the reloaded transcript still shows only the visitor's message and the assistant's final reply, not the tool-call or tool-result messages

#### Scenario: A chat's system/instruction message is never shown
- **WHEN** a chat has a persisted `role: "system"` message (e.g. from `chat.with_instructions`)
- **THEN** the transcript never displays it as a chat bubble, on initial load or after any later message is added

### Requirement: Retrieval details are available on demand, not auto-displayed
The system SHALL NOT automatically render retrieval source information as an assertion of relevance. Instead, when a `RetrievalLog` exists for an assistant message, the system SHALL provide an on-demand affordance that, when activated, displays that log's data (retrieved chunks with scores, top module, ansible_core_version, cost, response time) as-is, without filtering by relevance or confidence.

#### Scenario: A reply with retrieval data exposes an on-demand details view
- **WHEN** an assistant message has an associated `RetrievalLog`
- **THEN** the transcript shows a small affordance (not an inline claim) that, when activated, opens a view showing that log's retrieved chunks, scores, top module, cost, and response time

#### Scenario: A reply with no retrieval data shows no affordance
- **WHEN** an assistant message has no associated `RetrievalLog`
- **THEN** no retrieval-details affordance is shown for that message

#### Scenario: Retrieval details are shown regardless of relevance
- **WHEN** a `RetrievalLog`'s retrieved chunks scored poorly on the reranker (e.g. an off-topic message that still triggered a search)
- **THEN** the details view still shows that data honestly, with no threshold-based suppression or "no results" substitution
