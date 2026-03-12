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
      assert_match(/gem "brakeman"/, content)
      assert_match(/gem "bundle-audit"/, content)
      assert_match(/gem "letter_opener"/, content)
      assert_match(/gem "standard"/, content)
    end
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

    assert_file ".rubocop.yml", /standard/
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

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
