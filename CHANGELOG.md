# Changelog

All notable changes to this project will be documented in this file.

## [0.10.0] - 2026-10-21

### Changed

- `maquina:rack_attack` and `maquina:security` install a much wider scanner-path list, and a route guard that keeps it from breaking the host app.
  - The list names what a modern scanner reaches for first, not just the classic targets: cloud provider credentials (`service-account.json`, `firebase-adminsdk.json`), container runtime internals (`/var/run/secrets/...`, `/proc/self/environ`), infrastructure as code (`docker-compose.yml`, `terraform.tfstate`), bare secret files (`secrets.json`, `credentials.json`), dev-server artefacts (`__vite_rsc_findSourceMapURL`, `/@fs/...`), source maps, dotfile credentials and encoded path traversal.
  - Measured against 30,703 refused requests collected from five production apps, the list names 5.2% of the observed attack traffic before and 58.7% after.
  - The path is unhidden before it is matched, so `/api/orders/..%2Fadmin/config.json` is caught like `/api/orders/../admin/config.json`.
  - A public key is not a private key: `/public_key.pem` and `/pubkey.pem` are still served.

### Added

- `maquina:rack_attack` installs a **route guard**: a scanner rule stands down when the app itself routes the path, so a broad pattern cannot break a real route. The route table is read once, on the first request, and cached.
  - The guard stands down entirely when the app has a root catch-all route (`/*path`), because then every path "matches" the app and the guard would disable itself.
  - The `/graphql` pattern is only refused when the app does not serve GraphQL.

## [0.9.0] - 2026-10-19

### Added

- `--passkeys` option for `maquina:app`. It runs `maquina:passkeys` after `maquina:security`, so the `passkey/ip` throttle lands in the Rack::Attack rules.
  - It needs `--auth clave` and stops before changing anything without it.
  - The development passkey origin follows `--port`.
  - The home page, README and post-install message point to `/passkeys`.

## [0.8.1] - 2026-10-14

### Fixed

- `maquina:passkeys`:
  - The Remove button on `/passkeys` was red text on a red fill. It now uses the ghost variant, so the red text sits on a transparent background.
  - Renaming a passkey redirects with 303, the same as removing one.
  - The `passkey/ip` Rack::Attack throttle counts the client address Rails resolves through trusted proxies (`action_dispatch.remote_ip`), not `req.ip`. Behind kamal-proxy, Thruster or Cloudflare, `req.ip` is the proxy, so every visitor shared one bucket.

## [0.8.0] - 2026-10-14

### Added

- `maquina:passkeys` generator: passkey (WebAuthn) sign-in on top of `maquina:clave`, which it requires. The email code stays as the way in without a passkey.
  - **What it installs:**
    - The `webauthn` gem, used only to verify the ceremonies.
    - `config/initializers/webauthn.rb`.
    - The `Passkey` model and `User#webauthn_id`.
    - Sign-in endpoints (`POST /session/passkey_challenge`, `POST /session/passkey`) that ask for no email.
    - A `/passkeys` page to add, rename and remove passkeys.
    - Two Stimulus controllers built on the browser's own WebAuthn JSON helpers (`parse*OptionsFromJSON`, `toJSON()`); `@github/webauthn-json` is archived, so there is no JavaScript dependency.
    - A passkey button and autofill (conditional mediation) on the sign-in page.
    - EN/ES locales and a `passkey/ip` Rack::Attack throttle.
    - A `WebAuthn::FakeClient` test helper and an integration test covering the flow.
    - The passkey UI is rendered visible and refreshed on `turbo:morph`, so a morph refresh can't leave it hidden.
    - Sign-in and sign-in-again redirects are full page loads, so the flash survives and the new session gets a fresh CSRF token.
  - **Security choices:**
    - Every ceremony requires user verification, both in the options and in `verify`.
    - Challenges live in the session, are removed before verification, and expire after 5 minutes.
    - The returned user handle must match the passkey's owner, and blocked users are refused.
    - A signature counter that goes backwards is refused.
    - Adding or removing a passkey needs a sign-in from the last 30 minutes, so a stolen session cookie cannot plant a passkey that outlives it.
    - Production refuses to boot while the relying party is still `localhost`.
  - Every step is idempotent, and anything the generator cannot place safely is listed after the install.

### Fixed

- `maquina:clave --skip-registration` no longer links the sign-in page to `new_registration_path`. That route doesn't exist without sign-up, so the page raised. The link is now generated only along with the sign-up flow.

## [0.7.0] - 2026-10-14

### Added

- `maquina:csp_reports` generator -- a Content Security Policy violation report endpoint on top of `maquina:security`, in one command. Adds `CspReportsController` (`POST /csp-reports` by default, `--path` to change it; an API controller with no session or CSRF; both the legacy `report-uri` and the Reporting API body shapes; 64 KB cap), `Security::CspViolation` and `Security::CspViolationReport`, a `db/security_migrate` migration plus the table in `db/security_schema.rb`, a daily purge in `config/recurring.yml`, and a section on the backstage Security page. Reported URLs lose their query and fragment, and browser-extension violations are dropped. It points the policy's `report_uri` at the endpoint (no `report-to`, which switches Chrome to the batched Reporting API), gives anonymous requests a nonce (Rails' session-id nonce is empty without a session), takes the endpoint out of the general Rack::Attack throttle and caps it at 100 per 5 minutes per IP. Every step is idempotent, and anything it cannot place safely is listed after the install instead of being forced.

### Security

- `maquina:clave` encrypts the sign-in code at rest (`encrypts :code` on `EmailVerification`) and checks it in constant time through `EmailVerification#code_matches?` (`secure_compare`) in both the session and registration verification controllers, instead of comparing with `!=`. The generator writes Active Record encryption keys into `config/credentials.yml.enc` when they are missing; without a master key it tells you to run `bin/rails db:encryption:init`. Encrypted rather than digested because the mail goes out through `deliver_later`, whose job reloads the record and must read the code back.

- `maquina:clave` locks a sign-in or sign-up code after 5 wrong guesses (`EmailVerification::MAX_ATTEMPTS`, `#locked?`). Both verification controllers check the lock before the guess, expire the code on the spot and answer `code_locked` (new EN/ES copy), so a code absorbs a bounded number of guesses however many IPs an attacker rotates through.

## [0.6.0] - 2026-09-26

### Added

- `maquina:security` generator -- records every Rack::Attack refusal as a `Security::AbuseEvent` in its own `security` database and shows the last week at `<prefix>/security` behind the backstage Basic Auth (503 until credentials are set): throttled and blocked addresses (banned now, expired or not banned), the scanner paths requested, sign-in throttles, targeted hosts, refusals by day and the latest refusals. Adds the models, `db/security_schema.rb`, the `security:` database entries, a daily purge in `config/recurring.yml`, the controller, layout and views, and a Security tab in the admin navigation.
- `--login-path` option for `maquina:rack_attack`.
- An admin overview at the backstage prefix root (`BackstageDashboardController`, `admin` layout), installed by `maquina:solid_errors`, `maquina:mission_control_jobs` and `maquina:security`. It links each installed dashboard and has a `@metrics` slot for aggregate counts. An Overview tab leads the admin navigation.
- Self-contained Solid Errors mailer templates (`error_occurred.html.erb` / `.text.erb`), so `send_emails` is safe to turn on.

### Changed

- `maquina:rack_attack` now bans instead of only blocking: three scanner paths in 10 minutes bans an IP for 7 days (Fail2Ban), and 600 requests in 5 minutes bans it for 1 day (Allow2Ban). Backup-archive probes (`.zip`, `.sql`, `.tar.gz`, ...) count as scanner paths, sensitive files match anywhere in the path, `/rails/active_storage` is exempt from the scanner rule and the general throttle, and every refusal is logged as an `[ATTACK]` line. The rule names changed from `block-php`/`block-wordpress`/`block-sensitive-files`/`block-scanner-targets` to `fail2ban/scanners` and `allow2ban/flood`.
- `maquina:app` installs `maquina:security` (which brings the Rack::Attack rules) and its `database.yml` has a `security` database.
- The admin navigation of `maquina:solid_errors` and `maquina:mission_control_jobs` links the Security page.
- Solid Errors mounts at `<prefix>/errors` and Mission Control Jobs at `<prefix>/jobs`, instead of `<prefix>/solid_errors` and `<prefix>/mission_control_jobs`. The app generator's home page, README and post-install message use the new paths.
- The admin navigation and overview use icons maquina-components ships with a `class` attribute (`triangle_alert`, `inbox`, `layout_dashboard`), so none renders blank or oversized.

### Fixed

- The README's install line named the gem `maquina_generators`; the gem is `maquina-generators`.

## [0.5.0] - 2026-05-31

### Added

- `--agent` option for `maquina:solid_errors` generator -- read-only AI-agent triage tooling over the errors store: `ErrorsQuery`/`FailureTriage`/`ErrorRedactor` objects, a `bin/failures` JSON runner, and a stdio MCP server (`bin/failures-mcp`) exposing `list_failures`/`get_exception`/`top_exceptions`. Adds `gem "mcp"`. Failed jobs and request exceptions are read from a single sink with sensitive keys redacted before reaching the agent.
- `--mcp-http` option for `maquina:solid_errors` generator (implies `--agent`) -- mounts the read-only MCP tool surface over HTTP at `<prefix>/failures/mcp` behind the existing backstage Basic Auth, so a developer can query a deployed app remotely. Self-disables (503) until backstage credentials are set.
- `ApplicationJob` `around_perform` hook (injected unconditionally by `maquina:solid_errors`) attaching job class, arguments, and id to errors reported to `Rails.error`, so background-job failures appear in the Solid Errors dashboard with replayable context.
- Deploy-agnostic remote-access instructions (ssh / docker / kamal stdio tunneling, HTTP, and offline SQLite snapshot) in the generator post-install.

### Fixed

- Long failed-job error strings and arguments now wrap instead of overflowing in the Mission Control Jobs failed-jobs table and job detail views (`break-words overflow-wrap-anywhere`, with `line-clamp-2` in table cells).
- `maquina:app` now restores the gitignored `config/database.yml` from `config/database.yml.example`: `bin/setup` copies it before `db:prepare`, and (when a GitHub Actions workflow exists) a "Prepare database config" step is injected before the CI test step. Without this, fresh clones and CI ran with no `database.yml` and every Rails task failed.
- `maquina:app` now pins `standard` to `>= 1.54` in the generated Gemfile. The placeholder releases `1.34.0.1`/`1.35.0.1` carry a too-loose `rubocop ~> 1.62` requirement, so bundler backtracks onto them under rubocop version pressure and the resulting `standard` binary refuses to run.
- Documented the generated `.rubocop.yml` as standard.rb's runner bridge (not custom RuboCop rules) with header comments in the file and at the `standard` gem declaration, so downstream guidance and the generator agree.

## [0.4.1] - 2026-03-13

### Added

- Account model and multi-tenancy support to `maquina:clave` generator -- registration creates an Account in a transaction with the first user as admin.
- `belongs_to :account`, `role` enum (member/admin), and `name` validation to the clave User model.
- `delegate :account` to the clave Current model.
- Accounts migration and account/role columns to the users migration in clave generator.

## [0.4.0] - 2026-03-12

### Added

- Custom Tailwind-styled views (41 files) for Mission Control Jobs -- jobs, queues, workers, and recurring tasks dashboards.
- `MissionControlHelper` with `job_status_badge_variant` and `nav_icon_for_section` to the `maquina:mission_control_jobs` generator.
- Custom layout with application/server selection and tab navigation for Mission Control Jobs.
- `--copy-views` option for `maquina:mission_control_jobs` generator (default: true).
- Shared admin navigation bar linking Solid Errors and Mission Control Jobs dashboards, generated by both generators.
- Toast flash messages (`toaster` component + `toast_flash_messages` helper) to both admin layouts.
- `AuthenticationCleanupJob` as a daily recurring task (3am) in Solid Queue configuration.
- `BackstageController` now includes maquina_components helpers in both generators.

### Changed

- Solid Errors layout title from "Solid Errors" to "Admin - Errors".
- Solid Errors index tab styling -- updated spacing, added overflow handling, context-aware empty states.
- Replaced overmind with `bin/dev` across app generator and docs.

## [0.3.0] - 2026-03-04

### Added

- `maquina:registration` generator -- password-based authentication with multi-tenant Account model, user roles (admin/member), and Tailwind-styled registration/login views. Builds on top of the Rails 8 authentication generator.
- `--auth` option for `maquina:app` generator to choose between `none`, `clave`, or `registration` authentication during setup.
- `maquina:app` generator -- full application setup orchestrator with gems, Procfile, config files, environment setup, and sub-generator invocation.
- `maquina:solid_queue` generator -- Solid Queue background job processing setup.

### Fixed

- Bundler environment locking when running `bundle install` from generators.
- Mission Control Jobs configuration timing issues.
- Solid Errors sub-generator initializer conflicts.

## [0.2.0] - 2025-12-20

### Added

- `maquina:rack_attack` generator -- request protection with default security rules.
- `--copy-views` option for `maquina:solid_errors` generator.
- CI workflow for testing and linting.

## [0.1.0] - 2025-11-15

### Added

- `maquina:clave` generator -- passwordless email-code authentication with models, controllers, views, mailer, job, locale files, and migrations.
- `maquina:solid_errors` generator -- error tracking dashboard with HTTP authentication.
- `maquina:mission_control_jobs` generator -- job queue dashboard with HTTP authentication.
- `--skip-views` and `--skip-registration` options for clave generator.
