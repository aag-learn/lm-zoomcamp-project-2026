## ADDED Requirements

### Requirement: Text embedding endpoint
The system SHALL provide a `POST /embed` HTTP endpoint that accepts a batch of texts and returns a corresponding embedding vector for each, preserving input order.

#### Scenario: Embedding a batch of texts
- **WHEN** a client sends `POST /embed` with `{"texts": ["hello world", "install a package"]}`
- **THEN** the response contains `{"embeddings": [[...], [...]]}` with exactly two 384-dimensional vectors, where `embeddings[0]` corresponds to `texts[0]` and `embeddings[1]` corresponds to `texts[1]`

#### Scenario: Embedding an empty batch
- **WHEN** a client sends `POST /embed` with `{"texts": []}`
- **THEN** the response contains `{"embeddings": []}` without error

### Requirement: Reranking endpoint
The system SHALL provide a `POST /rerank` HTTP endpoint that accepts a query and a batch of candidate texts and returns a relevance score for each candidate, preserving input order.

#### Scenario: Reranking a batch of candidates
- **WHEN** a client sends `POST /rerank` with `{"query": "copy a file", "candidates": ["the copy module transfers files", "the apt module manages packages"]}`
- **THEN** the response contains `{"scores": [s0, s1]}` where `s0` corresponds to `candidates[0]` and `s1` corresponds to `candidates[1]`, and the score for the more relevant candidate (`"the copy module transfers files"`) is higher

#### Scenario: Reranking an empty candidate list
- **WHEN** a client sends `POST /rerank` with `{"query": "copy a file", "candidates": []}`
- **THEN** the response contains `{"scores": []}` without error

### Requirement: Models load once at startup
The system SHALL load both the embedding model and the reranking model exactly once, when the service process starts, not on a per-request basis.

#### Scenario: Repeated requests reuse the same loaded model
- **WHEN** two consecutive `POST /embed` requests are sent to a running service instance
- **THEN** both are served without any observable model-loading delay on the second request (the model was already resident in memory from startup)

### Requirement: Health endpoint reflects true readiness
The system SHALL expose a `GET /health` endpoint that returns a success status only after both models have finished loading into memory, not merely once the HTTP process has started.

#### Scenario: Health check during startup
- **WHEN** the container has just started and the models are still loading
- **THEN** `GET /health` does not return a success status until model loading has completed

#### Scenario: Health check once ready
- **WHEN** both models have finished loading
- **THEN** `GET /health` returns a success status

### Requirement: No ansible-doc/ansible-core dependency
The system SHALL NOT include `ansible-core` or invoke `ansible-doc` in this service — fetching Ansible module documentation is out of scope for this capability.

#### Scenario: Service image contains no ansible-core
- **WHEN** the embedder container's installed Python packages are inspected
- **THEN** `ansible-core` is not present among them

### Requirement: Service is reachable from the host
The system SHALL publish the service's port to the host machine, configurable via an `EMBEDDER_PORT` environment variable with a default value, so it can be tested directly without entering the container or joining the Docker network manually.

#### Scenario: Default port
- **WHEN** `docker compose up -d embedder` is run without `EMBEDDER_PORT` set
- **THEN** the service is reachable at `http://localhost:8001`

#### Scenario: Overridden port
- **WHEN** `EMBEDDER_PORT=9000` is set before `docker compose up -d embedder`
- **THEN** the service is reachable at `http://localhost:9000` instead

### Requirement: Automated curl-based verification script
The system SHALL provide a `curl`-based shell script that exercises every scenario in this spec against a running instance and exits non-zero if any scenario's expected behavior does not hold.

#### Scenario: Script passes against a healthy instance
- **WHEN** `embedder/test.sh` is run while the `embedder` service is up and healthy
- **THEN** it checks the embed, rerank, health, and empty-list scenarios above and exits `0` only if all of them pass

#### Scenario: Script fails on a broken contract
- **WHEN** `embedder/test.sh` is run against an instance that violates one of the above scenarios (e.g. `/embed` returns vectors in the wrong order)
- **THEN** the script exits non-zero and reports which check failed
