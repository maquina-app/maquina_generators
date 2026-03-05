# Changelog

All notable changes to this project will be documented in this file.

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
