## MODIFIED Requirements

### Requirement: Retrieved sources are cited in the interface
The system SHALL make retrieval source information available for each retrieval-grounded assistant reply, on demand rather than automatically displayed as an inline claim — see the `chat-interface` capability's "Retrieval details are available on demand, not auto-displayed" requirement for the exact mechanism.

#### Scenario: Citations visible under a grounded reply
- **WHEN** a visitor activates the retrieval-details affordance on an assistant reply that used retrieval
- **THEN** the source module(s) the reply was grounded in are shown, without being auto-displayed as an unqualified claim alongside the reply
