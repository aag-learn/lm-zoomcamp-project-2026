## Purpose

Run the application on real internet-facing infrastructure the user controls — a self-managed VM reached over HTTPS on a real domain — as a production deployment path additive to, and independent of, the existing local `docker compose` workflow.

## ADDED Requirements

### Requirement: The application is reachable over HTTPS on a real domain
The system SHALL serve the web application over HTTPS on the configured production domain, with automatic certificate provisioning, and SHALL NOT require the operator to manually obtain or install a TLS certificate.

#### Scenario: Visiting the production domain
- **WHEN** a visitor navigates to the production domain over HTTPS
- **THEN** they receive a valid, automatically-provisioned TLS certificate and reach the running application

### Requirement: Deploying to a fresh server provisions its own container runtime
The system SHALL provision whatever container runtime it needs on a target server that doesn't already have it, as part of the standard deploy/setup process, without requiring the operator to manually install it first.

#### Scenario: First deploy to a server with no container runtime installed
- **WHEN** the operator runs the deployment setup command against a freshly-provisioned server with no container runtime present
- **THEN** the deployment tooling installs it as part of setup, and the deploy proceeds without a separate manual installation step

### Requirement: New application versions deploy without visible downtime
The system SHALL only route visitor traffic to a new application version once it has confirmed that version is responding correctly, and SHALL keep serving the previous version until then.

#### Scenario: Deploying a new version while the app is receiving traffic
- **WHEN** an operator deploys a new version of the application
- **THEN** visitors continue to receive responses from a working version throughout the deploy, with no failed requests caused by the switch itself

### Requirement: Background job processing and the ML inference sidecar run as independently-built, independently-managed services
The system SHALL run the background job processor and the embedding/reranking service as their own deployable units, each built from its own image, separate from the public-facing web image.

#### Scenario: The job processor's image differs from the web image
- **WHEN** the background job processor is deployed
- **THEN** it runs from an image built specifically for it (carrying dependencies the public-facing web image does not need), not a copy of the web image running a different command

### Requirement: Container images are pushed to a registry reachable without a local container daemon
The system SHALL push and pull built container images using a registry and build path that don't require a container daemon on the machine issuing deploy commands, since builds execute on the target server itself over SSH.

#### Scenario: Deploying from a machine with no local container daemon
- **WHEN** the operator runs a deploy from a machine that has no running container daemon of its own
- **THEN** the image still builds (on the target server, over SSH) and pushes successfully to the registry

#### Scenario: The registry account is a real third-party account, but images themselves are public
- **WHEN** the deployment configuration references registry credentials
- **THEN** those credentials belong to a third-party container registry account the operator controls, and the images they authenticate for are public, not private

### Requirement: Database and dashboard data persist across redeploys
The system SHALL retain the production database's data and the monitoring dashboard's stored data across every redeploy and container restart, without operator intervention.

#### Scenario: Redeploying the application
- **WHEN** the operator deploys a new version of the application
- **THEN** existing chat history, retrieval logs, and monitoring dashboard data are unaffected by the redeploy

### Requirement: Monitoring dashboard configuration stays sourced from the repository
The system SHALL serve the monitoring dashboard's panel definitions and data source configuration from the same repository content used in local development, not from a separately-maintained production copy.

#### Scenario: A dashboard panel is edited in the repository and redeployed
- **WHEN** a dashboard definition in the repository changes and the application is redeployed
- **THEN** the production monitoring dashboard reflects that change, without a manual dashboard-editing step in production

### Requirement: Production secrets are sourced from a dedicated production secrets file, distinct from local development's
The system SHALL read production secrets from their own environment-variable-based secrets file, deliberately separate from the one used for local and containerized development, so the two environments can never accidentally share a secret value.

#### Scenario: Deploying after rotating a secret
- **WHEN** an operator updates a secret's value in the production secrets file and redeploys
- **THEN** the deployed application uses the updated value, with no separate secrets-management tool or store required

#### Scenario: Local development and production never share a secret value
- **WHEN** an operator sets a value in the local development secrets file
- **THEN** the production deployment is unaffected, since it reads from its own separate file

### Requirement: A fresh deployment's first-boot database preparation is self-healing
The system SHALL recover automatically, without operator intervention, if a service that depends on the database attempts to start before the database is ready during a fresh deployment's first boot.

#### Scenario: The background job processor starts before the database has finished initializing on a fresh deploy
- **WHEN** a completely fresh deployment boots the database and the background job processor together for the first time
- **THEN** the job processor recovers automatically and successfully prepares the database, without the operator needing to intervene or retry manually
