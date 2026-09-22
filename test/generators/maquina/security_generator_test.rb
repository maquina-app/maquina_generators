require "test_helper"
require "generators/maquina/security/security_generator"

class Maquina::Generators::SecurityGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::SecurityGenerator
  destination File.expand_path("../../tmp", __dir__)

  DATABASE_YML = <<~YAML
    default: &default
      adapter: sqlite3
      timeout: 5000

    development:
      primary:
        <<: *default
        database: storage/development.sqlite3
      errors:
        <<: *default
        database: storage/development_errors.sqlite3
        migrations_paths: db/errors_migrate

    # Warning: the test database is erased.
    test:
      primary:
        <<: *default
        database: storage/test.sqlite3

    production:
      primary:
        <<: *default
        database: storage/production.sqlite3
  YAML

  setup do
    prepare_destination

    mkdir_p("config")
    File.write(
      File.join(destination_root, "config/routes.rb"),
      "Rails.application.routes.draw do\nend\n"
    )

    File.write(
      File.join(destination_root, "Gemfile"),
      "source \"https://rubygems.org\"\n"
    )

    File.write(File.join(destination_root, "config/database.yml"), DATABASE_YML)
  end

  test "generates backstage controller with helpers" do
    run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage_controller.rb" do |content|
      assert_match(/class BackstageController < ActionController::Base/, content)
      assert_match(/helper MaquinaComponents::IconsHelper/, content)
      assert_match(/helper MaquinaComponents::EmptyHelper/, content)
    end
  end

  test "does not overwrite existing backstage controller" do
    mkdir_p("app/controllers")
    File.write(
      File.join(destination_root, "app/controllers/backstage_controller.rb"),
      "class BackstageController < ActionController::Base\n  # custom\nend\n"
    )

    run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage_controller.rb", /# custom/
  end

  test "installs the rack_attack rules when there is no initializer" do
    run_generator %w[--prefix /admin]

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(%r{fail2ban/scanners}, content)
      assert_match(%r{allow2ban/flood}, content)
      assert_match(/def self\.banned\?/, content)
      assert_match(%r{LOGIN_PATH = "/session"}, content)
    end
  end

  test "passes the login path to the rack_attack rules" do
    run_generator %w[--prefix /admin --login-path /sign_in]

    assert_file "config/initializers/rack_attack.rb", %r{LOGIN_PATH = "/sign_in"}
  end

  test "replaces an initializer without bans" do
    mkdir_p("config/initializers")
    File.write(
      File.join(destination_root, "config/initializers/rack_attack.rb"),
      "Rack::Attack.blocklist(\"block-php\") { |req| false }\n"
    )

    run_generator %w[--prefix /admin]

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_no_match(/block-php/, content)
      assert_match(/def self\.banned\?/, content)
    end
  end

  test "keeps an initializer that already bans" do
    mkdir_p("config/initializers")
    File.write(
      File.join(destination_root, "config/initializers/rack_attack.rb"),
      "class Rack::Attack\n  def self.banned?(ip) = false # custom\nend\n"
    )

    run_generator %w[--prefix /admin]

    assert_file "config/initializers/rack_attack.rb", /# custom/
  end

  test "records refusals with a subscriber of its own" do
    run_generator %w[--prefix /admin]

    assert_file "config/initializers/rack_attack_events.rb" do |content|
      assert_match(/subscribe\("rack\.attack"\)/, content)
      assert_match(/Rack::Attack\.banned\?\(req\.ip\)/, content)
      assert_match(/Security::AbuseEvent\.record!/, content)
      assert_match(/rescue => error/, content)
    end
  end

  test "generates models" do
    run_generator %w[--prefix /admin]

    assert_file "app/models/security/record.rb", /connects_to database: \{writing: :security\}/
    assert_file "app/models/security/abuse_event.rb" do |content|
      assert_match(/class Security::AbuseEvent < Security::Record/, content)
      assert_match(/RETENTION = 30\.days/, content)
      assert_match(/def self\.record!/, content)
    end
    assert_file "app/models/security/abuse_report.rb" do |content|
      assert_match(/class Security::AbuseReport/, content)
      assert_match(/Rack::Attack\.banned\?\(ip\)/, content)
      assert_no_match(/Arel.sql\("GROUP_CONCAT/, content)
    end
  end

  test "generates the security schema" do
    run_generator %w[--prefix /admin]

    assert_file "db/security_schema.rb" do |content|
      assert_includes content, "ActiveRecord::Schema[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}].define(version: 1)"
      assert_match(/create_table "abuse_events"/, content)
      assert_match(/index_abuse_events_on_ip_and_created_at/, content)
    end
  end

  test "adds a security database to every multi-database environment" do
    run_generator %w[--prefix /admin]

    assert_file "config/database.yml" do |content|
      %w[development test production].each do |env|
        assert_match(%r{  security:\n    <<: \*default\n    database: storage/#{env}_security\.sqlite3\n    migrations_paths: db/security_migrate\n}, content)
      end
      assert_match(%r{db/errors_migrate\n  security:\n}, content)
      assert_match(%r{test_security\.sqlite3\n    migrations_paths: db/security_migrate\n\nproduction:}, content)
      assert_match(/# Warning: the test database is erased\.\ntest:/, content)
      assert YAML.load(content, aliases: true).dig("production", "security", "database")
    end
  end

  test "does not duplicate the security database" do
    run_generator %w[--prefix /admin]
    run_generator %w[--prefix /admin]

    assert_file "config/database.yml" do |content|
      assert_equal 3, content.scan("  security:").length
    end
  end

  test "updates database.yml.example too" do
    File.write(File.join(destination_root, "config/database.yml.example"), DATABASE_YML)

    run_generator %w[--prefix /admin]

    assert_file "config/database.yml.example", %r{storage/production_security\.sqlite3}
  end

  test "nests a single-database sqlite environment under primary" do
    File.write(
      File.join(destination_root, "config/database.yml"),
      "default: &default\n  adapter: sqlite3\n\ndevelopment:\n  <<: *default\n  database: storage/development.sqlite3\n\ntest:\n  <<: *default\n  database: storage/test.sqlite3\n"
    )

    run_generator %w[--prefix /admin]
    run_generator %w[--prefix /admin]

    assert_file "config/database.yml" do |content|
      config = YAML.load(content, aliases: true)
      assert_equal "storage/development.sqlite3", config.dig("development", "primary", "database")
      assert_equal "storage/development_security.sqlite3", config.dig("development", "security", "database")
      assert_equal "sqlite3", config.dig("test", "security", "adapter")
      assert_equal 2, content.scan("  security:").length
    end
  end

  test "leaves a single-database environment on another adapter alone" do
    File.write(
      File.join(destination_root, "config/database.yml"),
      "development:\n  adapter: postgresql\n  database: app_development\n"
    )

    output = run_generator %w[--prefix /admin]

    assert_file "config/database.yml" do |content|
      assert_no_match(/security/, content)
    end
    assert_match(/Add a `security` database/, output)
  end

  test "schedules the purge in recurring.yml" do
    File.write(
      File.join(destination_root, "config/recurring.yml"),
      "production:\n  clear_solid_queue_finished_jobs:\n    command: \"SolidQueue::Job.clear_finished_in_batches\"\n    schedule: every hour\n"
    )

    run_generator %w[--prefix /admin]
    run_generator %w[--prefix /admin]

    assert_file "config/recurring.yml" do |content|
      assert_equal 1, content.scan("purge_abuse_events:").length
      assert_match(/Security::AbuseEvent\.expired\.delete_all/, content)
      assert YAML.load(content).dig("production", "purge_abuse_events", "schedule")
    end
  end

  test "adds gem to Gemfile" do
    run_generator %w[--prefix /admin]

    assert_file "Gemfile" do |content|
      assert_equal 1, content.scan('gem "rack-attack"').length
    end
  end

  test "generates controller behind backstage basic auth" do
    run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage/security_controller.rb" do |content|
      assert_match(/class Backstage::SecurityController < BackstageController/, content)
      assert_match(%r{layout "backstage/security"}, content)
      assert_match(/head :service_unavailable/, content)
      assert_match(/secure_compare/, content)
      assert_match(/credentials\.backstage/, content)
      assert_match(/ENV\["SECURITY_USER"\]/, content)
      assert_match(/ENV\["SECURITY_PASSWORD"\]/, content)
    end
  end

  test "generates controller with custom env var names" do
    run_generator %w[--prefix /admin --user-env-var ADMIN_USER --password-env-var ADMIN_PASSWORD]

    assert_file "app/controllers/backstage/security_controller.rb" do |content|
      assert_match(/ENV\["ADMIN_USER"\]/, content)
      assert_match(/ENV\["ADMIN_PASSWORD"\]/, content)
    end
  end

  test "adds route with prefix" do
    run_generator %w[--prefix /backstage]

    assert_file "config/routes.rb", %r{get "/backstage/security", to: "backstage/security#show", as: :backstage_security}
  end

  test "generates admin navigation partial with every tab" do
    run_generator %w[--prefix /admin]

    assert_file "app/views/layouts/_admin_navigation.html.erb" do |content|
      assert_match(%r{/admin/solid_errors}, content)
      assert_match(%r{/admin/mission_control_jobs}, content)
      assert_match(%r{/admin/security}, content)
    end
  end

  test "adds a Security tab to an existing admin navigation once" do
    nav = File.expand_path(
      "../../../lib/generators/maquina/mission_control_jobs/templates/app/views/layouts/_admin_navigation.html.erb.tt",
      __dir__
    )
    content = File.read(nav).gsub(/\n\s*<%%= link_to "<%= options\[:prefix\] %>\/security".*?<%% end %>\n/m, "\n")
      .gsub("<%%", "<%").gsub("<%= options[:prefix] %>", "/admin")
    refute_match(%r{/admin/security}, content)
    mkdir_p("app/views/layouts")
    File.write(File.join(destination_root, "app/views/layouts/_admin_navigation.html.erb"), content)

    run_generator %w[--prefix /admin]
    run_generator %w[--prefix /admin]

    assert_file "app/views/layouts/_admin_navigation.html.erb" do |result|
      assert_equal 1, result.scan("<span>Security</span>").length
      assert_match(%r{<span>Jobs</span>\n\s*<% end %>\n\n\s*<%= link_to "/admin/security"}, result)
    end
  end

  test "copies layout" do
    run_generator %w[--prefix /admin]

    assert_file "app/views/layouts/backstage/security.html.erb", /admin_navigation/
  end

  test "copies views by default" do
    run_generator %w[--prefix /admin]

    %w[show _addresses _banned _by_day _hosts _paths _recent _utc_time].each do |view|
      assert_file "app/views/backstage/security/#{view}.html.erb"
    end
    assert_file "app/views/backstage/security/show.html.erb" do |content|
      assert_match(/Rack::Attack::LOGIN_PATH/, content)
      assert_no_match(%r{admin/security|shared/}, content)
    end
  end

  test "does not copy views with --no-copy-views" do
    run_generator %w[--prefix /admin --no-copy-views]

    assert_no_file "app/views/backstage/security/show.html.erb"
  end

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
