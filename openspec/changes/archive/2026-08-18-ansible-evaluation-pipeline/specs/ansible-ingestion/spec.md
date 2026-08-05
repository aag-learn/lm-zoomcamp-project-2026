## MODIFIED Requirements

### Requirement: Module documentation is split into retrievable chunks
The system SHALL split each module's documentation into four distinct kinds of retrievable chunks — one overview chunk, one chunk per parameter, one chunk per usage example, and one chunk per return value — so that a single-fact question (a parameter's default, one example, one return value, or a module's deprecation status) can be answered by retrieving one focused chunk rather than an entire module's documentation.

#### Scenario: A module with multiple parameters yields one chunk per parameter
- **WHEN** a module documents N parameters
- **THEN** N distinct parameter chunks are produced for that module, each containing only that one parameter's description, type, default, and choices

#### Scenario: A module with multiple usage examples yields one chunk per example
- **WHEN** a module's documentation includes multiple named usage examples
- **THEN** each named example is stored as its own chunk, not combined with the others into a single chunk

#### Scenario: A module with multiple return values yields one chunk per return value
- **WHEN** a module documents N return values
- **THEN** N distinct return-value chunks are produced for that module, each containing only that one return value's description, type, and sample

#### Scenario: A module always yields exactly one overview chunk
- **WHEN** a module is chunked
- **THEN** exactly one overview chunk is produced, containing the module's summary description (independent of how many parameters, examples, or return values it has)

#### Scenario: A deprecated module's overview chunk states its deprecation
- **WHEN** a module's documentation marks it as deprecated
- **THEN** that module's overview chunk content includes its deprecation status and its replacement module (when one is documented), in addition to its summary description

#### Scenario: A non-deprecated module's overview chunk contains no deprecation content
- **WHEN** a module's documentation does not mark it as deprecated
- **THEN** that module's overview chunk content contains only its summary description, with no deprecation-related text
