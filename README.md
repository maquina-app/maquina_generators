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

#### Installation

Add to your Gemfile:

```ruby
gem "maquina_generators", group: :development
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
- **Colors/styling:** Edit view templates (default: indigo)
- **Email sender:** Edit `app/mailers/verification_mailer.rb`
- **Translations:** Edit `config/locales/clave.*.yml`

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
- **Route:** Mounts `SolidErrors::Engine` under a configurable prefix
- **Admin navigation:** Shared navigation bar linking the Solid Errors, Mission Control Jobs and Security dashboards
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

---

### Mission Control Jobs -- Job Queue Dashboard

**Mission Control Jobs** installs the [mission_control-jobs](https://github.com/rails/mission_control-jobs) gem with HTTP authentication and engine mounting.

#### What it generates

- **BackstageController:** Inherits from `ActionController::Base` with maquina_components helpers (bypasses app's ApplicationController concerns)
- **Helper:** `MissionControlHelper` with `job_status_badge_variant` and `nav_icon_for_section`
- **Initializer:** Sets base controller class, credentials-first auth with ENV variable fallback
- **Route:** Mounts `MissionControl::Jobs::Engine` under a configurable prefix
- **Admin navigation:** Shared navigation bar linking the Solid Errors, Mission Control Jobs and Security dashboards
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
```

---

### Rack Attack -- Request Protection

**Rack Attack** installs the [rack-attack](https://github.com/rack/rack-attack) gem with rules that ban vulnerability scanners and addresses that ignore the throttle.

#### What it generates

- **Initializer:** `config/initializers/rack_attack.rb` with the bans, throttles, safelist, 403 responder and an `[ATTACK]` log line per refusal. Its knobs are constants on `Rack::Attack` (`SCANNER_*`, `GENERAL_*`, `FLOOD_*`, `LOGIN_*`) and `Rack::Attack.banned?(ip)` answers whether an address is banned now.

#### Usage

```bash
rails g maquina:rack_attack
rails g maquina:rack_attack --login-path /sign_in   # Throttle a different sign-in path
```

The generator automatically runs `bundle install`.

#### Default Protections

- **Scanner ban (Fail2Ban):** three scanner paths in 10 minutes bans the IP for 7 days. Scanner paths are PHP files (`*.php`), WordPress paths (`wp-admin`, `wp-login`, etc.), sensitive files anywhere in the path (`.env`, `.git`, `/etc/passwd`, etc.), backup archives (`.zip`, `.sql`, `.tar.gz`, `.bak`, etc.) and scanner targets (`phpmyadmin`, `cgi-bin`, etc.). `/rails/active_storage` is exempt.
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
- **BackstageController**, **controller** (`Backstage::SecurityController`), **route** (`<prefix>/security`), **layout** and **views**: stats, throttled and banned addresses, blocked paths, sign-in throttles, targeted hosts, refusals by day, recent refusals (views skipped with `--no-copy-views`)
- **Admin navigation:** a Security tab, added to an existing `_admin_navigation` partial too

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
11. Invokes sub-generators: `maquina:rack_attack`, `maquina:mission_control_jobs`, `maquina:solid_errors`
12. Runs external installers: `solid_queue:install`, `solid_errors:install`, `solid_cache:install`, `solid_cable:install`, `maquina_components:install`
13. Restores custom layouts overwritten by gem installers
14. Configures multi-database `database.yml` (primary, queue, cache, cable, errors)
15. Creates a HomeController with root route
16. Generates a README and `database.yml.example`
17. Runs `db:prepare`

#### Usage

```bash
rails g maquina:app
rails g maquina:app --prefix /backstage --port 3100
rails g maquina:app --auth registration
```

#### Options

- `--prefix` (default: `/admin`) -- Base path prefix for backstage tools (Solid Errors, Mission Control Jobs)
- `--port` (default: `3000`) -- Default port for the development server
- `--auth` (default: `none`) -- Authentication type: `none`, `clave`, or `registration`

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
