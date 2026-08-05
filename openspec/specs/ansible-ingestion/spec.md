## Purpose

Populate the application's database with retrievable, embedded chunks of `ansible.builtin` module documentation, fetched from `ansible-doc` and refreshed automatically on a recurring schedule, so downstream retrieval and chat capabilities have real data to search.

## Requirements

### Requirement: Module documentation is fetched from ansible-doc
The system SHALL fetch structured documentation for every module in the `ansible.builtin` collection using the `ansible-doc` command-line tool, along with the currently installed `ansible-core` version.

#### Scenario: Successful fetch
- **WHEN** an ingestion run starts and `ansible-doc` is available
- **THEN** structured documentation is retrieved for every module in the `ansible.builtin` collection, together with the installed `ansible-core` version string

#### Scenario: Fetch failure aborts without touching existing data
- **WHEN** the `ansible-doc` invocation fails (non-zero exit status, or output that cannot be parsed as valid documentation)
- **THEN** the ingestion run aborts without modifying any previously stored module or chunk data

### Requirement: Module documentation is split into retrievable chunks
The system SHALL split each module's documentation into four distinct kinds of retrievable chunks — one overview chunk, one chunk per parameter, one chunk per usage example, and one chunk per return value — so that a single-fact question (a parameter's default, one example, one return value) can be answered by retrieving one focused chunk rather than an entire module's documentation.

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

### Requirement: Each chunk has a stable, deterministic identifier
The system SHALL assign every chunk a deterministic identifier derived from its source module and its specific parameter, example, or return value, so that the chunk representing the same logical piece of documentation has the same identifier across repeated ingestion runs.

#### Scenario: Re-running ingestion preserves chunk identity
- **WHEN** ingestion runs twice in a row against the same module set and the same `ansible-core` version
- **THEN** the chunk representing a given module's given parameter (or example, or return value) has the same identifier in both runs

### Requirement: Every chunk has a vector embedding
The system SHALL compute and store a vector embedding for every chunk's content, with no chunk left without a corresponding embedding.

#### Scenario: All chunks produced by a run are embedded
- **WHEN** an ingestion run produces a set of chunks
- **THEN** every chunk in that set has a stored embedding vector corresponding to its own content, and the number of stored embeddings equals the number of chunks

### Requirement: Chunks support both full-text and vector similarity search
The system SHALL persist each chunk such that it is findable both via full-text search over its content and via vector similarity search over its embedding.

#### Scenario: Full-text search finds a chunk by keyword
- **WHEN** a full-text search is run for a distinctive word appearing in a chunk's content
- **THEN** that chunk is returned among the results

#### Scenario: Vector similarity search finds a chunk by semantic content
- **WHEN** a vector similarity search is run using an embedding of a query that is semantically close to a chunk's content
- **THEN** that chunk is returned among the nearest results

### Requirement: Ingestion runs are atomic and version-tagged
The system SHALL replace the entire previous set of stored modules and chunks with a newly fetched set atomically — either the whole run succeeds and fully replaces prior data, or it fails and prior data is left completely intact — and SHALL tag every module and chunk produced by a run with the `ansible-core` version used to produce it.

#### Scenario: Successful run fully replaces prior data with a single consistent version
- **WHEN** an ingestion run completes successfully
- **THEN** the previous set of modules and chunks is entirely replaced by the new set, and every stored module and chunk is tagged with the same `ansible-core` version — the one active during that run

#### Scenario: A failed run leaves prior data intact
- **WHEN** an ingestion run fails partway through (e.g. the fetch step, the chunking step, or the embedding step raises an error)
- **THEN** the previously stored modules and chunks remain exactly as they were before the run started, with no partial or empty state visible to the rest of the application

### Requirement: Ingestion runs automatically on a recurring schedule
The system SHALL run the ingestion process automatically on a recurring schedule, without requiring an operator to manually trigger it for the application to stay populated.

#### Scenario: Scheduled run executes without manual intervention
- **WHEN** the application has been running for at least one full scheduled interval
- **THEN** at least one ingestion run has executed automatically, without an operator having manually triggered it
