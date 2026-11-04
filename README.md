# Maquina Generators

A collection of Rails generators from the Maquina umbrella. Each generator produces standalone code with no runtime gem dependency -- the gem is only needed at generation time.

## Available Generators

### Clave -- Passwordless Email-Code Authentication

**Clave** (Spanish: "code/key") generates a complete passwordless authentication system using email verification codes.

#### What it generates

- **Models:** `Account`, `User`, `Session`, `EmailVerification`, `Current`
- **Controllers:** Sign-in/sign-up flows with email code verification
- **Views:** Minimal, responsive forms styled with Tailwind CSS
- **Mailer:** Verification code emails (HTML + text)
- **Job:** Cleanup job for expired sessions and verifications
- **Locale files:** English and Spanish translations
- **Migrations:** 4 migrations (accounts, users, sessions, email_verifications)
- **Test helper:** `sign_in_as(user)` and `sign_out` for integration tests

Sign-in codes are encrypted at rest with Active Record encryption and compared in constant time. The generator adds the encryption keys to `config/credentials.yml.enc` when they are missing; without a master key, run `bin/rails db:encryption:init`.

#### Installation

Add to your Gemfile:

```ruby
gem "maquina-generators", group: :development
```

Run the generator:

```bash
rails g maquina:clave
```

Then:

```bash
rails db:migrate  # Run migrations
```

#### Options

```bash
rails g maquina:clave                        # Full install
rails g maquina:clave --skip-registration    # Sign-in only (no sign-up)
rails g maquina:clave --skip-views           # Skip view templates
```

#### Customization

All generated code lives in your app -- edit it directly:

- **Redirect after login:** Edit `app/controllers/concerns/authentication.rb` (`after_authentication_url`)
- **Session duration:** Edit `authentication.rb` (default: 30 days)
- **Code expiration:** Edit controllers (default: 15 minutes)
- **Cooldown between codes:** Edit `EmailVerification::COOLDOWN_MINUTES` (default: 15)
- **Wrong guesses before a code locks:** Edit `EmailVerification::MAX_ATTEMPTS` (default: 5)
- **Colors/styling:** Edit view templates (default: indigo)
- **Email sender:** Edit `app/mailers/verification_mailer.rb`
- **Translations:** Edit `config/locales/clave.*.yml`

### Passkeys -- Passkey Sign-In for Clave

**Passkeys** adds WebAuthn passkeys as a second way to sign in, on top of Clave. People add passkeys from a `/passkeys` page and sign in with Face ID, a fingerprint or a device PIN, either with a button or straight from the email field's autofill. The email code stays as the way in without a passkey, so removing every passkey never locks anyone out.

The [`webauthn`](https://github.com/cedarcode/webauthn-ruby) gem handles only the cryptography (attestation and assertion parsing, signature, origin, challenge and user-verification checks). The flow itself, including controllers, model, views and JavaScript, is generated into your app. There is no JavaScript dependency: the Stimulus controllers use the browser's own `PublicKeyCredential.parseCreationOptionsFromJSON` / `parseRequestOptionsFromJSON` / `toJSON()`. The names (`passkeys` table, `credential_id`, `Session::PasskeysController`) follow the passkeys work proposed for Rails itself (rails/rails#57100).

#### What it generates

- **Gem:** `webauthn ~> 3.4`
- **Initializer:** `config/initializers/webauthn.rb`. The relying party is `localhost` in development; production reads `WEBAUTHN_RP_ID` / `WEBAUTHN_ORIGINS` (or `webauthn:` in credentials) and refuses to boot without them, except during the asset build.
- **Models:** `Passkey` (credential id, public key, sign count, transports, AAGUID, backup flags, last used) and `User#webauthn_id`, a random user handle created on first use
- **Sign-in:** `Session::PasskeyChallengesController` and `Session::PasskeysController`. These need no email (discoverable credentials, empty allow-list), require user verification, use each challenge once and expire it after 5 minutes, and sign in through Clave's `start_new_session_for`. An unknown credential gets a 404 so the browser can forget it (`signalUnknownCredential`).
- **Management:** `PasskeysController` and `PasskeyChallengesController` to add, rename and remove passkeys. Adding or removing a passkey needs a sign-in from the last 30 minutes (`PasskeyReauthentication::REAUTHENTICATE_AFTER`).
- **Views and JavaScript:** `passkeys/index`, a `sessions/_passkey` partial rendered on the sign-in page (and `autocomplete="username webauthn"` on its email field), plus `passkey_sign_in_controller.js` and `passkey_registration_controller.js`
- **Migrations:** `add_webauthn_id_to_users`, `create_passkeys`
- **Locale files:** English and Spanish
- **Rack::Attack:** a `passkey/ip` throttle when `config/initializers/rack_attack.rb` exists
- **Tests:** a `register_passkey` and `sign_in_with_passkey(user)` helper on top of `WebAuthn::FakeClient`, loaded from `test/test_helper.rb`, and `test/integration/passkeys_test.rb` covering the flow. The test creates users the way Clave's `User` does, so adjust its `setup` if your model differs.

#### Usage

```bash
rails g maquina:clave      # first
rails g maquina:passkeys
rails db:migrate
```

Then link to `passkeys_path` from your account or settings page. Anything the generator cannot place safely (a `User` model or sign-in page that no longer has Clave's shape) is listed after the install instead of being forced.

#### Options

```bash
rails g maquina:passkeys               # Full install
rails g maquina:passkeys --skip-views  # Endpoints only; bring your own UI
```

#### Production

Passkeys are bound to a domain, and changing `rp_id` later orphans every saved passkey. Set it before the first user adds one:

```bash
WEBAUTHN_RP_ID=example.com
WEBAUTHN_ORIGINS=https://example.com,https://app.example.com
```

`rp_id` can be a parent of the origins' host. To serve passkeys across different domains, publish `/.well-known/webauthn` (Related Origin Requests).

#### Testing

- **Integration tests:** `register_passkey` and `sign_in_with_passkey(user)` go through the real endpoints with `WebAuthn::FakeClient`.
- **In a browser:** Chrome's virtual authenticator works in DevTools (More tools > WebAuthn) or over CDP (`WebAuthn.addVirtualAuthenticator` with `ctap2`, `internal`, a resident key and user verification). It answers the sign-in page's autofill request on its own, so loading `/session/new` signs you in without a click. To test the button, make `PublicKeyCredential.isConditionalMediationAvailable` return `false`.
- **Dev server on another port:** set `WEBAUTHN_ORIGINS=http://localhost:<port>`.

### OAuth -- OAuth 2.1 Sign-In for AI Clients

**OAuth** lets AI clients (the MCP Inspector, Claude, any MCP client) sign people in to your app on top of Clave. It is the authorization server behind `maquina:mcp`. Clients identify themselves with a Client ID Metadata Document (CIMD): the `client_id` is an `https` URL whose JSON names the client and its redirect URIs, so there is no dynamic registration and no client secret. Every flow is PKCE (`S256` only), and people sign in with the email code they already use.

No OAuth gem is added: the endpoints, models and fetcher are generated into your app.

#### What it generates

- **Migrations:** `create_oauth_clients`, `create_oauth_authorization_codes`, `create_access_tokens` (refresh tokens live on the access token row)
- **Models:** `OauthClient` (fetched metadata, refreshed after 24 hours), `OauthAuthorizationCode` (10-minute, single-use, PKCE-checked), `AccessToken` (1-hour access token, rotating refresh token, `read`/`write` scopes; only SHA-256 digests are stored) and `ConnectedApplication`, which groups a person's grants per client
- **CIMD fetcher:** `OauthClient::MetadataFetcher`, plain `Net::HTTP`. It refuses non-`https` URLs, literal IPs, hosts that resolve to loopback, private, link-local, unspecified or `100.64.0.0/10` addresses, redirects, bodies over 16 KB, responses slower than 3 seconds and documents whose `client_id` does not match
- **Discovery:** `GET /.well-known/oauth-authorization-server` and `GET /.well-known/oauth-protected-resource/mcp`
- **Authorize:** `Oauth::AuthorizationsController` at `/oauth/authorize`, the consent screen. A signed-out visitor signs in with Clave and lands back on the exact authorize URL. An unknown client or a redirect URI the client does not list gets an error page and is never redirected
- **Token and revoke:** `POST /oauth/token` (authorization code and refresh token grants) and `POST /oauth/revoke` (RFC 7009), JSON with `Cache-Control: no-store`
- **Connected apps:** `ConnectedApplicationsController` at `<prefix>/connected_apps`, where people see each connected client with its scopes and last use, and revoke it. Revoking stops its tokens at once
- **Gate:** `app/models/mcp.rb` with `Mcp.enabled_for?(user)`, written only if missing. Your app owns it
- **Rack::Attack:** `/mcp` and `/oauth/token` leave the per-IP throttle and flood ban (they are limited per token and per client instead), plus an `oauth/token/client` throttle of 30 per minute, when `config/initializers/rack_attack.rb` exists
- **Locale files:** English and Spanish (`config/locales/oauth.*.yml`)
- **Tests:** fixtures (`oauth_clients`, `oauth_authorization_codes`, `access_tokens`, and `mcp_*` users and account), `OauthTestHelper`, and tests for PKCE, code reuse and expiry, refresh rotation and reuse, `resource` and `iss` checks, the return-to after sign-in and revoking

#### Usage

```bash
rails g maquina:clave      # first
rails g maquina:oauth
rails db:migrate
```

Anything the generator cannot place safely (a Rack::Attack initializer that no longer has the expected shape) is listed after the install instead of being forced.

#### Options

```bash
rails g maquina:oauth                       # Full install
rails g maquina:oauth --skip-views          # Endpoints only; bring your own consent and Connected apps views
rails g maquina:oauth --prefix /account     # Connected apps at /account/connected_apps (default: /settings)
rails g maquina:oauth --flag beta_mcp       # Gate consent and Connected apps behind a feature flag
rails g maquina:oauth --quiet               # No post-install message
```

#### Feature flag

Without `--flag`, `Mcp.enabled_for?` returns `true` for everyone. With `--flag beta_mcp`, it reads `Rails.application.credentials.features.beta_mcp`, then `ENV["BETA_MCP"]`. When it is off for someone, consent answers `access_denied`, Connected apps is a 404, their MCP tools return nothing and `server/discover` still answers. Replace the method body with Flipper or a column when you need per-user rollout.

### MCP -- Model Context Protocol Server

**MCP** gives your app a standalone [MCP](https://modelcontextprotocol.io) server at `POST /mcp`, signed in through `maquina:oauth`. It speaks protocol `2026-07-28` over plain HTTP: no SSE, no sessions, no `mcp` gem. It ships a `whoami` tool that proves the wiring works, and `maquina:mcp_tool` adds more.

#### What it generates

- **Controller:** `McpController` (`ActionController::API`) with `McpAuthenticatable`, which reads the `Authorization: Bearer` token and checks that it was issued for `<base>/mcp`. A missing or bad token gets 401 with `WWW-Authenticate` pointing at the protected-resource metadata. `GET` and `DELETE /mcp` return 405
- **Protocol:** `server/discover` (no token needed), `tools/list` and `tools/call`. The `Mcp-Method` and `Mcp-Name` headers must match the body, `params._meta` must carry protocol `2026-07-28`, and the JSON-RPC error codes live in one table in `McpController`. A write tool called with a `read` token gets 403 `insufficient_scope`
- **Rate limit:** 120 requests per minute per token (per IP without one)
- **CORS:** `config/initializers/mcp_cors.rb`, a small Rack middleware for `/mcp`, `/oauth/token`, `/oauth/revoke` and `/.well-known/oauth-*` (never `/oauth/authorize`); no `rack-cors`
- **Registry:** `app/models/mcp/` -- `Mcp::Tools` (dispatch), `Mcp::ToolDefinitions` (what a user sees), `Mcp::ToolError` and `Mcp::UserScope` (the token's user and the records it may reach). Every file in `app/models/mcp/tools/` is a module with `DEFINITIONS`, `WRITE_TOOLS`, `ADMIN_ONLY` and one method per tool. Arguments are checked against the tool's JSON Schema (required keys, types, enums) before dispatch
- **Tool:** `app/models/mcp/tools/app.rb` with `whoami` (email, granted scope, server and protocol versions, and the flag state with `--flag`), written only if missing
- **Tests:** `McpTestHelper` (`mcp_post`, `oauth_token_for`), `test/integration/mcp_flow_test.rb` (discover, authorize, consent, token, `whoami`, revoke, 401), `test/integration/mcp_conformance_test.rb` and `test/models/mcp/tools_test.rb`, which fails when a tool that writes is missing from its module's `WRITE_TOOLS`

#### Usage

```bash
rails g maquina:oauth      # first
rails g maquina:mcp
rails db:migrate
```

Or all at once: `rails g maquina:app --auth clave --mcp`.

#### Options

```bash
rails g maquina:mcp                     # Full install
rails g maquina:mcp --flag beta_mcp     # Set the flag in app/models/mcp.rb if it still says FLAG = nil
rails g maquina:mcp --prefix /account   # The Connected apps prefix you gave maquina:oauth (default: /settings)
rails g maquina:mcp --skip-views        # You ran maquina:oauth --skip-views: the flow test skips the consent and Connected apps pages
rails g maquina:mcp --quiet             # No post-install message
```

#### Connecting a client

Start the app and run the [MCP Inspector](https://github.com/modelcontextprotocol/inspector):

```bash
bin/dev
npx @modelcontextprotocol/inspector
```

Choose the Streamable HTTP transport, enter `http://localhost:3000/mcp` and connect. The Inspector discovers the authorization server, sends you to the consent screen (sign in with your email code if needed), and lists `whoami`. The app then shows up at `/settings/connected_apps`, where revoking it makes the next call answer 401.

#### Operational tools from other generators

When `app/models/mcp/tools.rb` exists, these generators also write an MCP tool module. Every one is `ADMIN_ONLY`: only users with the `admin` role see or call them, and a member's token gets "unknown tool". Lists are capped at 50 rows and times are ISO 8601 UTC.

| Generator | Tool file | Tools |
|-----------|-----------|-------|
| `maquina:solid_errors` | `tools/solid_errors.rb` | `list_failures`, `get_failure`, `top_exceptions` (copies `ErrorsQuery`, `FailureTriage` and `ErrorRedactor` into `app/agents/` if missing) |
| `maquina:solid_queue` | `tools/solid_queue.rb` | `queue_status`, `list_failed_jobs`, `get_failed_job` (arguments redacted); `retry_failed_job` with `--mcp-write` |
| `maquina:security` | `tools/security.rb` | `recent_blocks`, `security_summary` |
| `maquina:csp_reports` | `tools/csp_reports.rb` | `list_csp_reports`, `csp_report_summary` |

The install order does not matter. A sibling run after `maquina:mcp` writes its own tool file. `maquina:mcp` run after the siblings backfills a tool file for each one it finds (`config/initializers/solid_errors.rb`, `config/solid_queue.yml` or `config/queue.yml`, `app/models/security/abuse_event.rb`, `csp_violations` in `db/security_schema.rb`), using the read-only Solid Queue variant. Existing tool files are never overwritten, and without MCP the siblings write and print nothing about it.

### MCP Tool -- Add a Tool to the MCP Server

**MCP Tool** adds a tool to `app/models/mcp/tools/app.rb`: its JSON Schema definition, a method stub and a test, without editing the registry by hand. It needs `maquina:mcp`.

#### Usage

```bash
rails g maquina:mcp_tool list_posts status:enum[draft,published]? limit:integer?
rails g maquina:mcp_tool publish_post id:integer --write
```

#### Arguments

- `NAME`: lowercase letters, digits and underscores, starting with a letter. A name already in `tools/app.rb` changes nothing; a name in another tool file stops the generator.
- `name:type`: `string`, `integer`, `number`, `boolean` or `enum[a,b]` (a string limited to those values). A trailing `?` makes the argument optional; every other argument is required.

#### Options

```bash
rails g maquina:mcp_tool NAME [arg:type ...]           # Read-only tool (readOnlyHint: true)
rails g maquina:mcp_tool NAME [arg:type ...] --write   # Needs the write scope; added to WRITE_TOOLS
rails g maquina:mcp_tool NAME --quiet                  # No "Items to finish" message
```

#### What it generates

- The definition in `DEFINITIONS`, the name in `WRITE_TOOLS` with `--write`, and `def self.<name>(scope:, ...)` that raises `Mcp::ToolError, "<name> is not implemented yet"`. If a marker comment in `tools/app.rb` is gone, the snippet is printed instead.
- `test/models/mcp/tools/<name>_test.rb`: listed for a `read` token, -32602 for a missing required argument, 403 `insufficient_scope` for a `read` token with `--write`, and a skipped cross-user test (a record owned by `users(:mcp_other)` must come back as not found) to fill in.

Afterwards, write the description for the model (plain English, units stated), the method body (reach records through `scope.records(:posts)` or `scope.find(:posts, id)` so a tool never sees another user's data) and the cross-user test setup.

### Registration -- Password-Based Authentication with Accounts

**Registration** generates a password-based authentication system with multi-tenant account support. It builds on top of the Rails 8 authentication generator, adding an Account model (tenant), user roles, and a registration flow.

#### What it generates

- **Runs Rails authentication generator** first (`bin/rails generate authentication`)
- **Account model:** `Account` with `name` field and `has_many :users`
- **Updated User model:** Adds `belongs_to :account`, `role` enum (admin/member), `name` field
- **Updated Current model:** Adds `account` delegation through the user
- **Registration controller:** Creates Account + User (admin role) together in a transaction
- **Views:** Tailwind-styled registration form and updated login form with indigo color scheme
- **Locale files:** English and Spanish translations
- **Migrations:** `create_accounts` and `add_account_fields_to_users`

#### Usage

```bash
rails g maquina:registration
```

Then:

```bash
bundle install    # Install bcrypt
rails db:migrate  # Run migrations
```

#### Options

```bash
rails g maquina:registration                # Full install
rails g maquina:registration --skip-views   # Skip view templates
```

#### Customization

All generated code lives in your app -- edit it directly:

- **Account fields:** Edit `app/models/account.rb` to add more tenant fields
- **User roles:** Edit `app/models/user.rb` to customize the role enum
- **Registration flow:** Edit `app/controllers/registrations_controller.rb`
- **Colors/styling:** Edit view templates (default: indigo)
- **Translations:** Edit `config/locales/registration.*.yml`

---

### Solid Errors -- Error Tracking Dashboard

**Solid Errors** installs the [solid_errors](https://github.com/fractaledmind/solid_errors) gem with HTTP authentication and engine mounting.

#### What it generates

- **BackstageController:** Inherits from `ActionController::Base` (bypasses app's ApplicationController concerns)
- **Initializer:** Credentials-first auth with ENV variable fallback, database connection config
- **Route:** Mounts `SolidErrors::Engine` at `<prefix>/errors`
- **Mailer templates:** Self-contained `error_occurred` HTML and text templates, so `send_emails` works without the dashboard's helpers
- **Admin navigation:** Shared navigation bar with Overview, Errors, Jobs and Security tabs
- **Admin overview:** `BackstageDashboardController` at the prefix root with cards for each installed dashboard and a `@metrics` slot for your own aggregate counts; answers 503 until backstage credentials are set
- **Custom layout:** Tailwind-styled layout with admin navigation and toast flash messages
- **Stimulus controllers:** `clipboard_controller.js` and `backtrace_filter_controller.js`
- **Custom views:** Tailwind-styled views to override the gem defaults (included by default, use `--no-copy-views` to skip)

#### Usage

```bash
rails g maquina:solid_errors --prefix /admin
rails g maquina:solid_errors --prefix /admin --no-copy-views   # Skip custom views
```

The generator automatically runs `bundle install`. After running, execute `bin/rails generate solid_errors:install` (decline the initializer overwrite to keep your config), then `bin/rails db:migrate`.

#### Options

```bash
rails g maquina:solid_errors --prefix /admin                          # Default (with custom views)
rails g maquina:solid_errors --prefix /admin --no-copy-views          # Without custom views
rails g maquina:solid_errors --prefix /backstage \
  --user-env-var ADMIN_USER --password-env-var ADMIN_PASSWORD         # Custom env vars
```

#### Authentication

Credentials are resolved in order:

1. `Rails.application.credentials.backstage.username` / `.password`
2. `ENV["SOLID_ERRORS_USER"]` / `ENV["SOLID_ERRORS_PASSWORD"]` (configurable)

#### MCP

With `maquina:mcp` installed, it also writes admin-only MCP tools (`list_failures`, `get_failure`, `top_exceptions`) to `app/models/mcp/tools/solid_errors.rb`. See [Operational tools from other generators](#operational-tools-from-other-generators). The old `--mcp-http` endpoint is gone; `--agent` still generates `bin/failures` and the stdio `bin/failures-mcp`.

---

### Mission Control Jobs -- Job Queue Dashboard

**Mission Control Jobs** installs the [mission_control-jobs](https://github.com/rails/mission_control-jobs) gem with HTTP authentication and engine mounting.

#### What it generates

- **BackstageController:** Inherits from `ActionController::Base` with maquina_components helpers (bypasses app's ApplicationController concerns)
- **Helper:** `MissionControlHelper` with `job_status_badge_variant` and `nav_icon_for_section`
- **Initializer:** Sets base controller class, credentials-first auth with ENV variable fallback
- **Route:** Mounts `MissionControl::Jobs::Engine` at `<prefix>/jobs`
- **Admin navigation:** Shared navigation bar with Overview, Errors, Jobs and Security tabs
- **Admin overview:** `BackstageDashboardController` at the prefix root with cards for each installed dashboard and a `@metrics` slot for your own aggregate counts; answers 503 until backstage credentials are set
- **Custom layout:** Tailwind-styled layout with admin navigation, toast flash messages, application/server selection, and tab navigation
- **Custom views:** Tailwind-styled views for jobs, queues, workers, and recurring tasks (included by default, use `--no-copy-views` to skip)

#### Usage

```bash
rails g maquina:mission_control_jobs --prefix /admin
rails g maquina:mission_control_jobs --prefix /admin --no-copy-views   # Skip custom views
```

The generator automatically runs `bundle install`.

#### Options

```bash
rails g maquina:mission_control_jobs --prefix /admin                  # Default (with custom views)
rails g maquina:mission_control_jobs --prefix /admin --no-copy-views  # Without custom views
rails g maquina:mission_control_jobs --prefix /backstage \
  --user-env-var ADMIN_USER --password-env-var ADMIN_PASSWORD         # Custom env vars
```

#### Authentication

Credentials are resolved in order:

1. `Rails.application.credentials.backstage.username` / `.password`
2. `ENV["MISSION_CONTROL_JOBS_USER"]` / `ENV["MISSION_CONTROL_JOBS_PASSWORD"]` (configurable)

---

### Solid Queue -- Background Job Processing

**Solid Queue** installs the [solid_queue](https://github.com/rails/solid_queue) gem as the Active Job backend with configuration and Procfile.dev integration.

#### What it generates

- **Config:** `config/solid_queue.yml` with default dispatcher/worker settings
- **Application config:** Sets `config.active_job.queue_adapter = :solid_queue` (skipped in test environment)
- **Procfile.dev:** Appends `solid_queue: bin/rails solid_queue:start`
- **Migrations:** Runs `solid_queue:install:migrations`

#### Usage

```bash
rails g maquina:solid_queue
```

The generator automatically runs `bundle install` and installs migrations.

#### Options

```bash
rails g maquina:solid_queue                      # Default (sqlite3)
rails g maquina:solid_queue --database postgresql # PostgreSQL
rails g maquina:solid_queue --mcp-write           # Also generate the retry_failed_job MCP tool
```

With `maquina:mcp` installed, it also writes admin-only MCP tools (`queue_status`, `list_failed_jobs`, `get_failed_job`) to `app/models/mcp/tools/solid_queue.rb`. `--mcp-write` adds `retry_failed_job`, which needs the `write` scope.

---

### Rack Attack -- Request Protection

**Rack Attack** installs the [rack-attack](https://github.com/rack/rack-attack) gem with rules that ban vulnerability scanners and addresses that ignore the throttle.

#### What it generates

- **Initializer:** `config/initializers/rack_attack.rb` with the bans, throttles, safelist, 403 responder and an `[ATTACK]` log line per refusal. Its knobs are constants on `Rack::Attack` (`SCANNER_*`, `GENERAL_*`, `FLOOD_*`, `LOGIN_*`) and `Rack::Attack.banned?(ip)` answers whether an address is banned now.
- **Route guard:** `Rack::Attack.app_route?(path)` answers whether the app itself routes a path, and `Rack::Attack.route_guard?` whether the guard is active (it stands down when the app has a root catch-all).

#### Usage

```bash
rails g maquina:rack_attack
rails g maquina:rack_attack --login-path /sign_in   # Throttle a different sign-in path
```

The generator automatically runs `bundle install`.

#### Default Protections

- **Scanner ban (Fail2Ban):** three scanner paths in 10 minutes bans the IP for 7 days. Scanner paths are PHP files (`*.php`), WordPress paths (`wp-admin`, `wp-login`, etc.), sensitive files anywhere in the path (`.env`, `.git`, `/etc/passwd`, etc.), backup archives (`.zip`, `.sql`, `.tar.gz`, `.bak`, etc.) and scanner targets (`phpmyadmin`, `cgi-bin`, etc.). `/rails/active_storage` is exempt.
  - The list also names what a modern scanner reaches for first: cloud provider credentials (`service-account.json`, `firebase-adminsdk.json`), container runtime internals (`/var/run/secrets/...`, `/proc/self/environ`), infrastructure as code (`docker-compose.yml`, `terraform.tfstate`), bare secret files (`secrets.json`, `credentials.json`), dev-server artefacts (`__vite_rsc_findSourceMapURL`, `/@fs/...`), source maps, dotfile credentials and encoded path traversal (`..%2F`).
  - The path is unhidden before it is matched, so an encoded traversal is caught like a plain one. A public key is not a private key: `/public_key.pem` is still served.
- **Route guard:** a scanner rule stands down when the app itself routes the path, so a broad pattern cannot break a real route. The route table is read once, on the first request, and cached. The guard stands down entirely when the app has a root catch-all route (`/*path`), because then every path would "match" the app.
- **Flood ban (Allow2Ban):** 600 requests in 5 minutes (twice the general throttle) bans the IP for 1 day.
- **Throttles:** 300 requests/5min per IP (general; `/assets` and `/rails/active_storage` exempt), 5 `POST /session`/20s per IP
- **Safelists:** Localhost (`127.0.0.1`, `::1`)
- **Responses:** 403 Forbidden for blocklisted and banned, 429 Too Many Requests for throttled

Bans live in `Rails.cache`, so they need a shared cache store (Solid Cache) in production. Customize rules in `config/initializers/rack_attack.rb`. To see the refusals, add `maquina:security`.

---

### Security -- Rack::Attack with an Abuse Dashboard

**Security** records every Rack::Attack refusal in its own database and summarises the last week on a backstage page next to Solid Errors and Mission Control Jobs.

#### What it generates

- **Rack::Attack rules:** runs `maquina:rack_attack` unless `config/initializers/rack_attack.rb` already defines `Rack::Attack.banned?` (an older initializer without it is replaced)
- **Subscriber:** `config/initializers/rack_attack_events.rb` writes a `Security::AbuseEvent` per throttled, blocked or banned request; a failed write never turns a 403 into a 500
- **Models:** `Security::Record` (`connects_to` the `security` database), `Security::AbuseEvent` (30-day retention), `Security::AbuseReport` (the page's figures)
- **Database:** `db/security_schema.rb` and a `security:` entry in every multi-database environment of `config/database.yml` (and `config/database.yml.example`)
- **Retention:** a daily `purge_abuse_events` task in `config/recurring.yml`
- **BackstageController**, **controller** (`Backstage::SecurityController`), **route** (`<prefix>/security`), **layout** and **views**: stats, throttled addresses, blocked addresses (banned now, expired or not yet banned), scanner paths, sign-in throttles, targeted hosts, refusals by day, recent refusals (views skipped with `--no-copy-views`)
- **Admin navigation:** a Security tab, added to an existing `_admin_navigation` partial too
- **Admin overview:** the shared dashboard at the prefix root, if Solid Errors or Mission Control Jobs have not installed it already

#### What the page shows

The last 7 days of refusals, top five of each, read from `Security::AbuseEvent` through `Security::AbuseReport`. It is a briefing, not a log viewer: no filters, no pagination. Times are UTC.

- **Stats:** refused requests, throttled, blocked or banned, and distinct addresses
- **Throttled addresses:** over the general or sign-in limit, busiest first, with the rules they hit
- **Blocked addresses:** every address a blocklist refused, marked **Banned now** (Rack::Attack's own answer at render time), **Expired**, or **Not banned** -- an address with a strike or two on the scanner rule, or a slow scanner that stays under three paths in ten minutes
- **Most requested blocked paths:** what the scanners were after. A banned address is refused on every path, its ordinary pages included, so only the paths `Rack::Attack.scanner_path?` recognises are listed
- **Sign-in throttles:** addresses refused on `POST <login-path>`, kept apart so scanner noise never buries them
- **Targeted hosts:** which hostnames the refusals were aimed at
- **By day:** throttled, blocked and banned per day, zeros kept so a spike reads against its neighbours
- **Recent refusals:** the last 20, newest first

#### Usage

```bash
rails g maquina:security --prefix /admin
bin/rails db:prepare
```

The generator automatically runs `bundle install`. The page needs maquina_components.

#### Options

```bash
rails g maquina:security --prefix /admin                      # Default
rails g maquina:security --prefix /admin --login-path /sign_in  # Different sign-in path
rails g maquina:security --prefix /admin --no-copy-views      # Without views
rails g maquina:security --prefix /backstage \
  --user-env-var ADMIN_USER --password-env-var ADMIN_PASSWORD  # Custom env vars
```

#### Authentication

HTTP Basic Auth, with credentials resolved in order:

1. `Rails.application.credentials.backstage.username` / `.password`
2. `ENV["SECURITY_USER"]` / `ENV["SECURITY_PASSWORD"]` (configurable)

The page answers 503 until one of them is set, so it is never left open.

#### Trying it locally

Localhost is safelisted, so your own requests are never refused. Rack::Attack trusts `X-Forwarded-For` from `127.0.0.1`, so send one to stand in for another address:

```bash
for path in /wp-login.php /.env /backup.zip /; do
  curl -s -o /dev/null -w "%{http_code} $path\n" -H "X-Forwarded-For: 203.0.113.10" http://localhost:3000$path
done
# 403 /wp-login.php
# 403 /.env
# 403 /backup.zip   <- third scanner path: banned for 7 days
# 403 /             <- banned, so every path is refused
```

Development's `:memory_store` keeps bans inside the server process, so they reset on restart and a `bin/rails runner` script cannot see them. Production needs a shared store (Solid Cache).

---

### CSP Reports -- Content Security Policy Violation Endpoint

**CSP Reports** gives the browser somewhere to send Content Security Policy violations and shows them on the Security page. It needs `maquina:security`, whose `security` database stores them.

#### What it generates

- **Controller:** `CspReportsController` at `POST /csp-reports` -- an API controller with no session or CSRF that accepts both the legacy `report-uri` body and the Reporting API body, capped at 64 KB. Reported URLs lose their query and fragment, and browser-extension violations are dropped
- **Models:** `Security::CspViolation` (30-day retention) and `Security::CspViolationReport` (the page's figures)
- **Database:** a migration in `db/security_migrate` and the `csp_violations` table in `db/security_schema.rb`
- **Retention:** a daily `purge_csp_violations` task in `config/recurring.yml`
- **Security page:** a section listing the last 7 days of violations, most frequent first
- **Policy:** points `report_uri` at the endpoint in `config/initializers/content_security_policy.rb` (no `report-to`, which switches Chrome to the batched Reporting API) and gives anonymous requests a nonce -- Rails' session-id nonce is empty without a session
- **Rack::Attack:** takes the endpoint out of the general throttle and caps it at 100 reports per 5 minutes per IP

Every step is idempotent. Anything it cannot place safely is listed after the install instead of being forced.

#### Usage

```bash
rails g maquina:csp_reports
rails g maquina:csp_reports --path /security/csp-reports   # Different endpoint path
bin/rails db:migrate
```

Watch the Security page while the policy is report-only, then set `content_security_policy_report_only = false` to enforce it.

---

### App -- Full Application Setup (Orchestrator)

**App** is a meta-generator that sets up a complete Rails application in one command. Run it after `rails new myapp --css tailwind`.

#### What it does

1. Adds development, runtime, and production gems (brakeman, standard, rails-i18n, maquina-components, aws-sdk-s3, etc.)
2. Creates `Procfile.dev`
3. Creates `.rubocop.yml`, `.standard.yml`, appends to `.gitignore`
4. Creates `config/initializers/generators.rb`
5. Configures development (letter_opener) and production (APPLICATION_HOST) environments
6. Configures `field_error_proc` and Solid Queue in `application.rb`
7. Installs Action Text and Active Storage
8. Sets up ActiveStorage JavaScript imports
9. Adds turbo morphing, `yield :head`, and simplifies `<main>` tag in layout
10. Optionally installs authentication (`maquina:clave` or `maquina:registration`)
11. Invokes sub-generators: `maquina:mission_control_jobs`, `maquina:solid_errors`
12. Runs external installers: `solid_queue:install`, `solid_errors:install`, `solid_cache:install`, `solid_cable:install`, `maquina_components:install`, then `maquina:security` (which installs the `maquina:rack_attack` rules), `maquina:passkeys` with `--passkeys`, and `maquina:oauth` plus `maquina:mcp` with `--mcp`
13. Restores custom layouts overwritten by gem installers
14. Configures multi-database `database.yml` (primary, queue, cache, cable, errors, security)
15. Creates a HomeController with root route
16. Generates a README and `database.yml.example`
17. Runs `db:prepare`

#### Usage

```bash
rails g maquina:app
rails g maquina:app --prefix /backstage --port 3100
rails g maquina:app --auth registration
rails g maquina:app --auth clave --passkeys
rails g maquina:app --auth clave --mcp
rails g maquina:app --auth clave --mcp --mcp-flag beta_mcp
```

#### Options

- `--prefix` (default: `/admin`) -- Base path prefix for backstage tools (Solid Errors, Mission Control Jobs, Security)
- `--port` (default: `3000`) -- Default port for the development server
- `--auth` (default: `none`) -- Authentication type: `none`, `clave`, or `registration`
- `--passkeys` (default: `false`) -- Adds passkey sign-in with `maquina:passkeys`. It needs `--auth clave` and refuses to run without it. The passkey origin follows `--port`, and the home page links to `/passkeys`.
- `--mcp` (default: `false`) -- Adds the OAuth-backed MCP server with `maquina:oauth` and `maquina:mcp`, after Security and Passkeys so the Rack::Attack rules and the admin tools from the other generators land. It needs `--auth clave` and refuses to run without it. The README and post-install message point to `/settings/connected_apps` and the MCP Inspector.
- `--mcp-flag NAME` -- Passed to both as `--flag NAME`, to gate MCP access behind a feature flag.

#### After running

```bash
bin/rails credentials:edit                # set backstage username/password
bin/dev
```

---

## Adding New Generators

Create a new folder under `lib/generators/maquina/`:

```
lib/generators/maquina/your_generator/
  your_generator_generator.rb
  USAGE
  templates/
    ...
```

The generator class should be `Maquina::Generators::YourGeneratorGenerator` and it will be available as `rails g maquina:your_generator`.

## Development

```bash
bundle install
rake test
bundle exec standardrb       # Lint
bundle exec standardrb --fix # Auto-fix
```

## License

MIT License. See [LICENSE.txt](LICENSE.txt).
