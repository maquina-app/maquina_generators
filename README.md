# Maquina Generators

A collection of Rails generators from the Maquina umbrella. Each generator produces standalone code with no runtime gem dependency -- the gem is only needed at generation time.

## Available Generators

### Clave -- Passwordless Email-Code Authentication

**Clave** (Spanish: "code/key") generates a complete passwordless authentication system using email verification codes.

#### What it generates

- **Models:** `User`, `Session`, `EmailVerification`, `Current`
- **Controllers:** Sign-in/sign-up flows with email code verification
- **Views:** Minimal, responsive forms styled with Tailwind CSS
- **Mailer:** Verification code emails (HTML + text)
- **Job:** Cleanup job for expired sessions and verifications
- **Locale files:** English and Spanish translations
- **Migrations:** 3 migrations (users, sessions, email_verifications)
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
- **Admin navigation:** Shared navigation bar linking Solid Errors and Mission Control Jobs dashboards
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
- **Admin navigation:** Shared navigation bar linking Solid Errors and Mission Control Jobs dashboards
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

**Rack Attack** installs the [rack-attack](https://github.com/rack/rack-attack) gem with default security rules to block common vulnerability scans and throttle abusive requests.

#### What it generates

- **Initializer:** `config/initializers/rack_attack.rb` with blocklists, safelists, and throttles

#### Usage

```bash
rails g maquina:rack_attack
```

The generator automatically runs `bundle install`.

#### Default Protections

- **Blocklists:** PHP files (`*.php`), WordPress paths (`wp-admin`, `wp-login`, etc.), sensitive files (`.env`, `.git`, `/etc/passwd`, etc.), scanner targets (`phpmyadmin`, `cgi-bin`, etc.)
- **Safelists:** Localhost (`127.0.0.1`, `::1`)
- **Throttles:** 300 requests/5min per IP (general), 5 login attempts/20s per IP
- **Responses:** 403 Forbidden for blocklisted, 429 Too Many Requests for throttled

Customize rules in `config/initializers/rack_attack.rb`.

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
