## Purpose

Restrict the deployed application to a single, known operator — every page requires signing in, with no self-service way for anyone else to gain access.

## Requirements

### Requirement: Every application route requires an authenticated session
The system SHALL require a signed-in session to access any page or feature of the application, with no exceptions, and SHALL redirect an unauthenticated visitor to sign in before continuing to their originally-requested page.

#### Scenario: Visiting any page while signed out
- **WHEN** a visitor without a signed-in session requests any page of the application (chat, monitoring, evaluation, or any other route)
- **THEN** they are redirected to sign in before seeing that page's content

#### Scenario: Reaching the originally-requested page after signing in
- **WHEN** an unauthenticated visitor is redirected to sign in while trying to reach a specific page, and then signs in successfully
- **THEN** they land on the page they originally requested, not an unrelated default page

### Requirement: Exactly one user account exists, with no self-service registration
The system SHALL NOT provide any way for a visitor to create their own account. The one account that can sign in is provisioned by the operator, not by application users.

#### Scenario: No registration path exists
- **WHEN** a visitor without an account looks for a way to sign up
- **THEN** no registration page or self-service account-creation flow exists anywhere in the application

### Requirement: The one account is provisioned automatically on first deployment
The system SHALL create the one operator account automatically the first time the application's database is initialized, from operator-configured credentials, without requiring a manual setup step after deployment.

#### Scenario: A completely fresh deployment
- **WHEN** the application is deployed for the very first time, against a database with no existing data
- **THEN** the configured operator account exists and can sign in immediately, without the operator running any additional command after the deploy finishes

### Requirement: There is no self-service password reset
The system SHALL NOT provide a self-service "forgot password" or password-reset flow.

#### Scenario: A visitor looks for a password reset option
- **WHEN** a visitor on the sign-in page has forgotten the password
- **THEN** no self-service password-reset link or flow is available
