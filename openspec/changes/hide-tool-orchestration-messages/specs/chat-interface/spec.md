## ADDED Requirements

### Requirement: Visitor-facing transcript excludes internal tool-orchestration messages
The system SHALL display, in the chat transcript, only the visitor's own messages and the assistant's final reply content — and SHALL NOT display raw tool-call invocations or raw tool-result content as chat bubbles, even though those messages are persisted internally.

#### Scenario: A reply that uses a tool shows only the final answer
- **WHEN** an assistant reply is generated using one or more tool calls
- **THEN** the transcript displays the visitor's message and the assistant's final reply content, and does not display the tool-call invocation or the tool's raw result as a separate chat entry

#### Scenario: A reply that doesn't use a tool is unaffected
- **WHEN** an assistant reply is generated without any tool calls
- **THEN** the transcript displays it exactly as before, with no change in behavior

#### Scenario: Reloading the page still hides orchestration messages
- **WHEN** a visitor reloads a conversation that included a tool-using reply
- **THEN** the reloaded transcript still shows only the visitor's message and the assistant's final reply, not the tool-call or tool-result messages

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
