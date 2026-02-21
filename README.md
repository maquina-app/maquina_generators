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
```

## License

MIT License. See [LICENSE.txt](LICENSE.txt).
