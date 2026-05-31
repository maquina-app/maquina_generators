require "test_helper"
require "generators/maquina/app/app_generator"

class Maquina::Generators::AppGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::AppGenerator
  destination File.expand_path("../../tmp", __dir__)

  setup do
    prepare_destination

    mkdir_p("config/environments")
    mkdir_p("config/initializers")
    mkdir_p("app/views/layouts")
    mkdir_p("app/javascript")

    File.write(
      File.join(destination_root, "Gemfile"),
      "source \"https://rubygems.org\"\n"
    )

    File.write(
      File.join(destination_root, "config/routes.rb"),
      "Rails.application.routes.draw do\nend\n"
    )

    File.write(
      File.join(destination_root, "config/application.rb"),
      <<~RUBY
        require_relative "boot"
        require "rails/all"

        module TestApp
          class Application < Rails::Application
            config.load_defaults 7.2
          end
        end
      RUBY
    )

    File.write(
      File.join(destination_root, "config/environments/development.rb"),
      "Rails.application.configure do\n  config.cache_classes = false\nend\n"
    )

    File.write(
      File.join(destination_root, "config/environments/production.rb"),
      "Rails.application.configure do\n  config.cache_classes = true\nend\n"
    )

    File.write(
      File.join(destination_root, "app/views/layouts/application.html.erb"),
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>TestApp</title>
          </head>
          <body>
            <%= yield %>
          </body>
        </html>
      HTML
    )

    File.write(
      File.join(destination_root, "app/javascript/application.js"),
      "// Entry point for the build script\n"
    )

    File.write(
      File.join(destination_root, "config/database.yml"),
      <<~YAML
        default: &default
          adapter: sqlite3
          pool: 5
          timeout: 5000

        development:
          <<: *default
          database: storage/development.sqlite3

        test:
          <<: *default
          database: storage/test.sqlite3

        production:
          <<: *default
          database: storage/production.sqlite3
      YAML
    )

    File.write(File.join(destination_root, ".gitignore"), "/log/*\n/tmp/*\n")
  end

  test "adds development gems to Gemfile" do
    run_generator

    assert_file "Gemfile" do |content|
      assert_match(/gem "brakeman", group: :development/, content)
      assert_match(/gem "bundle-audit", group: :development/, content)
      assert_match(/gem "letter_opener", group: :development/, content)
      assert_match(/gem "standard", ">= 1.54", group: :development/, content)
    end
  end

  test "pins standard above the broken placeholder releases" do
    run_generator

    # 1.34.0.1 / 1.35.0.1 are inoperative placeholder gems; the constraint must exclude them
    assert_file "Gemfile", /gem "standard", ">= 1\.54"/
  end

  test "adds runtime gems to Gemfile" do
    run_generator

    assert_file "Gemfile" do |content|
      assert_match(/gem "rails-i18n"/, content)
      assert_match(/gem "maquina-components"/, content)
    end
  end

  test "removes rubocop-rails-omakase gem from Gemfile" do
    File.write(
      File.join(destination_root, "Gemfile"),
      "source \"https://rubygems.org\"\ngem \"rubocop-rails-omakase\", require: false\n"
    )

    run_generator

    assert_file "Gemfile" do |content|
      assert_no_match(/rubocop-rails-omakase/, content)
    end
  end

  test "adds production gems to Gemfile" do
    run_generator

    assert_file "Gemfile", /gem "aws-sdk-s3", group: :production/
  end

  test "creates Procfile.dev with default port" do
    run_generator

    assert_file "Procfile.dev" do |content|
      assert_match(/web: bin\/rails server -p 3000/, content)
      assert_match(/css: bin\/rails tailwindcss:watch/, content)
      assert_match(/solid_queue: bin\/rails solid_queue:start/, content)
    end
  end

  test "creates Procfile.dev with custom port" do
    run_generator %w[--port 3100]

    assert_file "Procfile.dev", /web: bin\/rails server -p 3100/
  end

  test "creates Procfile.dev" do
    run_generator

    assert_file "Procfile.dev"
  end

  test "creates rubocop config" do
    run_generator

    assert_file ".rubocop.yml" do |content|
      assert_match(/standard/, content)
      assert_match(/runner bridge, not custom RuboCop rules/, content)
    end
  end

  test "creates standard config" do
    run_generator

    assert_file ".standard.yml", /ruby_version/
  end

  test "appends database.yml to gitignore" do
    run_generator

    assert_file ".gitignore", /config\/database\.yml/
  end

  test "creates generators initializer" do
    run_generator

    assert_file "config/initializers/generators.rb" do |content|
      assert_match(/stylesheets false/, content)
    end
  end

  test "configures development environment with letter_opener" do
    run_generator

    assert_file "config/environments/development.rb" do |content|
      assert_match(/letter_opener/, content)
      assert_match(/localhost/, content)
    end
  end

  test "configures production environment with APPLICATION_HOST" do
    run_generator

    assert_file "config/environments/production.rb" do |content|
      assert_match(/APPLICATION_HOST/, content)
    end
  end

  test "configures field_error_proc in application" do
    run_generator

    assert_file "config/application.rb" do |content|
      assert_match(/field_error_proc/, content)
    end
  end

  test "configures solid_queue in application" do
    run_generator

    assert_file "config/application.rb" do |content|
      assert_match(/queue_adapter = :solid_queue/, content)
      assert_match(/solid_queue\.connects_to/, content)
    end
  end

  test "adds yield :head to layout" do
    run_generator

    assert_file "app/views/layouts/application.html.erb" do |content|
      assert_match(/yield :head/, content)
    end
  end

  test "adds turbo morphing to layout body" do
    run_generator

    assert_file "app/views/layouts/application.html.erb" do |content|
      assert_match(/data-turbo-refresh-method/, content)
    end
  end

  test "replaces styled main tag with plain main tag" do
    File.write(
      File.join(destination_root, "app/views/layouts/application.html.erb"),
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>TestApp</title>
          </head>
          <body>
            <main class="container mx-auto mt-28 px-5 flex">
              <%= yield %>
            </main>
          </body>
        </html>
      HTML
    )

    run_generator

    assert_file "app/views/layouts/application.html.erb" do |content|
      assert_match(/<main>/, content)
      assert_no_match(/container mx-auto mt-28 px-5 flex/, content)
    end
  end

  test "creates home controller" do
    run_generator

    assert_file "app/controllers/home_controller.rb", /class HomeController/
  end

  test "creates home view" do
    run_generator

    assert_file "app/views/home/index.html.erb", /Tools for Rails developers/
  end

  test "adds root route" do
    run_generator

    assert_file "config/routes.rb", /root "home#index"/
  end

  test "adds root route when commented root exists" do
    File.write(
      File.join(destination_root, "config/routes.rb"),
      "Rails.application.routes.draw do\n  # root \"posts#index\"\nend\n"
    )

    run_generator

    assert_file "config/routes.rb", /root "home#index"/
  end

  test "creates README" do
    run_generator

    assert_file "README.md" do |content|
      assert_match(/Getting Started/, content)
      assert_match(/bin\/dev/, content)
    end
  end

  test "configures multiple databases for all environments" do
    run_generator

    assert_file "config/database.yml" do |content|
      %w[development test production].each do |env|
        assert_match(/#{env}:\n  primary:/, content, "Missing primary database for #{env}")
        assert_match(/#{env}_queue\.sqlite3/, content, "Missing queue database for #{env}")
        assert_match(/#{env}_cache\.sqlite3/, content, "Missing cache database for #{env}")
        assert_match(/#{env}_cable\.sqlite3/, content, "Missing cable database for #{env}")
        assert_match(/#{env}_errors\.sqlite3/, content, "Missing errors database for #{env}")
      end
      assert_match(/migrations_paths: db\/queue_migrate/, content)
      assert_match(/migrations_paths: db\/cache_migrate/, content)
      assert_match(/migrations_paths: db\/cable_migrate/, content)
      assert_match(/migrations_paths: db\/errors_migrate/, content)
    end
  end

  test "shows post-install message content" do
    output = run_generator

    assert_match(/Your Rails app is ready!/, output)
    assert_match(/credentials:edit/, output)
    assert_match(/bin\/dev/, output)
  end

  test "does not install authentication by default" do
    run_generator

    assert_no_file "app/models/account.rb"
    assert_no_file "app/controllers/registrations_controller.rb"
  end

  test "shows auth info in post-install when auth option is set" do
    output = run_generator %w[--auth registration]

    assert_match(/Authentication \(registration\)/, output)
    assert_match(/registrations\/new/, output)
  end

  test "injects database.yml restore into bin/setup" do
    write_bin_setup

    run_generator

    assert_file "bin/setup" do |content|
      assert_match(/unless File\.exist\?\("config\/database\.yml"\)/, content)
      assert_match(/FileUtils\.cp "config\/database\.yml\.example", "config\/database\.yml"/, content)
      # placed after bundle install, before preparing the database
      assert_operator content.index("bundle install"), :<, content.index("database.yml.example")
      assert_operator content.index("database.yml.example"), :<, content.index("Preparing database")
    end
  end

  test "does not duplicate the bin/setup database restore" do
    write_bin_setup

    run_generator
    run_generator

    assert_file "bin/setup" do |content|
      assert_equal 1, content.scan('FileUtils.cp "config/database.yml.example"').length
    end
  end

  test "skips bin/setup when it does not exist" do
    run_generator

    assert_no_file "bin/setup"
  end

  test "injects database.yml restore before the CI test step" do
    write_ci_workflow

    run_generator

    assert_file ".github/workflows/ci.yml" do |content|
      assert_match(/- name: Prepare database config/, content)
      assert_match(/run: cp config\/database\.yml\.example config\/database\.yml/, content)
      assert_operator content.index("Prepare database config"), :<, content.index("- name: Run tests")
    end
  end

  test "does not duplicate the CI database restore" do
    write_ci_workflow

    run_generator
    run_generator

    assert_file ".github/workflows/ci.yml" do |content|
      assert_equal 1, content.scan("Prepare database config").length
    end
  end

  test "skips CI workflow when it does not exist" do
    run_generator

    assert_no_file ".github/workflows/ci.yml"
  end

  private

  def write_bin_setup
    mkdir_p("bin")
    File.write(
      File.join(destination_root, "bin/setup"),
      <<~RUBY
        #!/usr/bin/env ruby
        require "fileutils"

        APP_ROOT = File.expand_path("..", __dir__)

        def system!(*args)
          system(*args, exception: true)
        end

        FileUtils.chdir APP_ROOT do
          system! "gem install bundler --conservative"
          system("bundle check") || system!("bundle install")

          puts "\\n== Preparing database =="
          system! "bin/rails db:prepare"
        end
      RUBY
    )
  end

  def write_ci_workflow
    mkdir_p(".github/workflows")
    File.write(
      File.join(destination_root, ".github/workflows/ci.yml"),
      <<~YAML
        name: CI
        on: [push]
        jobs:
          test:
            runs-on: ubuntu-latest
            steps:
              - name: Checkout code
                uses: actions/checkout@v4
              - name: Run tests
                env:
                  RAILS_ENV: test
                run: bin/rails db:test:prepare test
      YAML
    )
  end

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
