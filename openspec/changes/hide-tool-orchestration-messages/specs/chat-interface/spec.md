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
