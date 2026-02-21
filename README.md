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
bundle install    # Install bcrypt
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

### Solid Errors -- Error Tracking Dashboard

**Solid Errors** installs the [solid_errors](https://github.com/fractaledmind/solid_errors) gem with HTTP authentication and engine mounting.

#### What it generates

- **BackstageController:** Inherits from `ActionController::Base` (bypasses app's ApplicationController concerns)
- **Initializer:** Credentials-first auth with ENV variable fallback, database connection config
- **Route:** Mounts `SolidErrors::Engine` under a configurable prefix
- **Custom views:** Optionally copies custom Tailwind-styled views to override the gem defaults

#### Usage

```bash
rails g maquina:solid_errors --prefix /admin
rails g maquina:solid_errors --prefix /admin --copy-views   # Include custom views
```

The generator automatically runs `bundle install` and `solid_errors:install`. After running, execute `bin/rails db:migrate`.

#### Options

```bash
rails g maquina:solid_errors --prefix /admin                          # Default env vars
rails g maquina:solid_errors --prefix /admin --copy-views             # With custom views
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

- **BackstageController:** Inherits from `ActionController::Base` (bypasses app's ApplicationController concerns)
- **Initializer:** Sets base controller class, credentials-first auth with ENV variable fallback
- **Route:** Mounts `MissionControl::Jobs::Engine` under a configurable prefix

#### Usage

```bash
rails g maquina:mission_control_jobs --prefix /admin
```

The generator automatically runs `bundle install`.

#### Options

```bash
rails g maquina:mission_control_jobs --prefix /admin                  # Default env vars
rails g maquina:mission_control_jobs --prefix /backstage \
  --user-env-var ADMIN_USER --password-env-var ADMIN_PASSWORD         # Custom env vars
```

#### Authentication

Credentials are resolved in order:

1. `Rails.application.credentials.backstage.username` / `.password`
2. `ENV["MISSION_CONTROL_JOBS_USER"]` / `ENV["MISSION_CONTROL_JOBS_PASSWORD"]` (configurable)

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
