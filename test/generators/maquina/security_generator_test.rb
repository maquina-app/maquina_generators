require "test_helper"
require "generators/maquina/security/security_generator"
require "generators/maquina/mcp/mcp_generator"

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
    write_host_app
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
      assert_match(/Rack::Attack\.scanner_path\?\(path\)/, content)
      assert_match(/def blocked_addresses/, content)
      assert_match(/def scanner_paths/, content)
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
      assert_match(/<span>Overview<\/span>/, content)
      assert_match(%r{"/admin/errors"}, content)
      assert_match(%r{"/admin/jobs"}, content)
      assert_match(%r{"/admin/security"}, content)
    end
  end

  # The Overview tab points at the prefix root, so a standalone install needs
  # the dashboard behind it.
  test "installs the backstage dashboard with a Security card" do
    run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage_dashboard_controller.rb" do |content|
      assert_match(/class BackstageDashboardController < BackstageController/, content)
      assert_match(/before_action :require_backstage_credentials\n\s+before_action :authenticate_backstage/, content)
      assert_match(/head :service_unavailable/, content)
    end
    assert_file "app/views/layouts/admin.html.erb", /admin_navigation/
    assert_file "app/views/backstage_dashboard/index.html.erb" do |content|
      assert_match(/defined\?\(Security::AbuseEvent\)/, content)
      assert_match(%r{"/admin/security"}, content)
    end
    assert_file "config/routes.rb", %r{get "/admin" => "backstage_dashboard#index"}
  end

  test "does not duplicate the dashboard route when run twice" do
    run_generator %w[--prefix /admin]
    run_generator %w[--prefix /admin]

    assert_file "config/routes.rb" do |content|
      assert_equal 1, content.scan("backstage_dashboard#index").length
    end
  end

  # solid_errors, mission_control_jobs and security each ship the shared admin
  # navigation and dashboard; whichever runs first writes them, so they must match.
  test "ships the same shared backstage templates as the other dashboards" do
    generators = File.expand_path("../../../lib/generators/maquina", __dir__)
    shared = %w[
      app/views/layouts/_admin_navigation.html.erb.tt
      app/views/layouts/admin.html.erb
      app/controllers/backstage_dashboard_controller.rb
      app/views/backstage_dashboard/index.html.erb.tt
    ]

    shared.each do |path|
      ours = File.read(File.join(generators, "security/templates", path))
      %w[solid_errors mission_control_jobs].each do |other|
        assert_equal File.read(File.join(generators, other, "templates", path)), ours,
          "#{path} differs between security and #{other}"
      end
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
      assert_match(/<svg[^>]*class="size-4"[^>]*><path d="M20 13c0 5/, result[/<%= link_to "\/admin\/security".*?<% end %>/m])
      assert_match(/shrink-0 items-center gap-1\.5 whitespace-nowrap border-b-2/, result)
    end
  end

  test "copies layout" do
    run_generator %w[--prefix /admin]

    assert_file "app/views/layouts/backstage/security.html.erb", /admin_navigation/
  end

  test "copies views by default" do
    run_generator %w[--prefix /admin]

    %w[show _addresses _blocked _by_day _hosts _paths _recent _utc_time].each do |view|
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

  test "writes nothing about MCP without maquina:mcp" do
    output = run_generator %w[--prefix /admin]

    assert_no_file "app/models/mcp/tools/security.rb"
    assert_no_file "test/models/mcp/tools/security_test.rb"
    assert_no_match(/mcp/i, output)
  end

  test "installs the read-only admin MCP tools when maquina:mcp is present" do
    write_mcp_registry

    output = run_generator %w[--prefix /admin]

    assert_file "app/models/mcp/tools/security.rb" do |content|
      assert_match(/module Mcp\n  module Tools\n    module Security\n/, content)
      assert_match(/ADMIN_ONLY = true/, content)
      assert_match(/WRITE_TOOLS = %w\[\]\.freeze/, content)
      %w[recent_blocks security_summary].each do |tool|
        assert_match(/name: "#{tool}"/, content)
        assert_match(/def self\.#{tool}\(scope:/, content)
      end
      assert_match(/::Security::AbuseEvent\.recent/, content)
      assert_no_match(/readOnlyHint: false/, content)
    end
    assert_file "test/models/mcp/tools/security_test.rb" do |content|
      assert_match(/users\(:mcp_member\)/, content)
      assert_match(/-32602/, content)
    end
    assert_match(%r{app/models/mcp/tools/security\.rb}, output)
  end

  test "generated MCP files are valid Ruby" do
    write_mcp_registry

    run_generator %w[--prefix /admin]

    %w[app/models/mcp/tools/security.rb test/models/mcp/tools/security_test.rb].each do |path|
      assert RubyVM::InstructionSequence.compile(File.read(File.join(destination_root, path)))
    end
  end

  test "keeps an existing MCP tool file" do
    write_mcp_registry
    FileUtils.mkdir_p(File.join(destination_root, "app/models/mcp/tools"))
    File.write(File.join(destination_root, "app/models/mcp/tools/security.rb"), "# custom tools\n")

    run_generator %w[--prefix /admin]

    assert_file "app/models/mcp/tools/security.rb", "# custom tools\n"
  end

  test "the rack_attack rules can lift a ban" do
    run_generator %w[--prefix /admin]

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/def self\.unban!\(ip\)\n    Fail2Ban\.reset\("scanner:\#\{ip\}", findtime: SCANNER_FINDTIME\)\n    Allow2Ban\.reset\("flood:\#\{ip\}", findtime: GENERAL_PERIOD\)/, content)
    end
  end

  test "adds unban_address as a write tool with --mcp-write" do
    write_mcp_registry

    output = run_generator %w[--prefix /admin --mcp-write]

    assert_file "app/models/mcp/tools/security.rb" do |content|
      assert_match(/WRITE_TOOLS = %w\[unban_address\]\.freeze/, content)
      assert_match(/name: "unban_address"/, content)
      assert_match(/def self\.unban_address\(scope:, ip:\)/, content)
      assert_match(/::Rack::Attack\.unban!\(address\)/, content)
      assert_match(/raise IPAddr::InvalidAddressError if ip\.include\?\("\/"\)/, content)
    end
    assert_match(/unban_address \(needs the write scope\)/, output)
  end

  test "both MCP tool variants are valid Ruby" do
    write_mcp_registry

    [%w[--prefix /admin], %w[--prefix /admin --mcp-write]].each do |args|
      FileUtils.rm_f(File.join(destination_root, "app/models/mcp/tools/security.rb"))
      run_generator args

      assert RubyVM::InstructionSequence.compile(File.read(File.join(destination_root, "app/models/mcp/tools/security.rb")))
    end
  end

  test "--mcp-write adds unban! to rules written before it existed" do
    run_generator %w[--prefix /admin]
    path = File.join(destination_root, "config/initializers/rack_attack.rb")
    File.write(path, File.read(path).sub(/\n  # Lifts both bans.*?\n  end\n/m, "\n"))
    assert_no_match(/unban!/, File.read(path))
    write_mcp_registry

    run_generator %w[--prefix /admin --mcp-write]

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_equal 1, content.scan("def self.unban!(ip)").size
      assert_match(/Allow2Ban\.banned\?\("flood:\#\{ip\}"\)\n  end\n\n  # Lifts both bans/, content)
    end
  end

  test "--mcp-write says how to add unban! to rules it cannot find its place in" do
    mkdir_p("config/initializers")
    File.write(File.join(destination_root, "config/initializers/rack_attack.rb"), "class Rack::Attack\n  def self.banned?(ip) = false # custom\nend\n")
    write_mcp_registry

    output = run_generator %w[--prefix /admin --mcp-write]

    assert_file "config/initializers/rack_attack.rb", /# custom/
    assert_match(/does not define/, output)
    assert_match(/def self\.unban!\(ip\)/, output)
  end

  test "running twice with maquina:mcp changes nothing the second time" do
    write_mcp_registry

    run_generator %w[--prefix /admin]
    first = snapshot
    run_generator %w[--prefix /admin]

    assert_equal first, snapshot
  end

  test "running before or after maquina:mcp ends in the same files" do
    sibling_first = in_fresh_app do
      run_generator %w[--prefix /admin]
      run_mcp_generator
    end
    mcp_first = in_fresh_app do
      run_mcp_generator
      run_generator %w[--prefix /admin]
    end

    assert sibling_first.key?("app/models/mcp/tools/security.rb")
    assert sibling_first.key?("test/models/mcp/tools/security_test.rb")
    # Both generators add routes at the top of the draw block, so only the
    # order of the routes depends on which ran first.
    assert_equal sibling_first.delete("config/routes.rb").to_s.lines.sort, mcp_first.delete("config/routes.rb").to_s.lines.sort
    assert_equal sibling_first, mcp_first
  end

  private

  def write_host_app
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

  # app/models/mcp/tools.rb is what tells a sibling generator maquina:mcp ran.
  def write_mcp_registry
    FileUtils.mkdir_p(File.join(destination_root, "app/models/mcp"))
    File.write(File.join(destination_root, "app/models/mcp/tools.rb"), "module Mcp\n  module Tools\n  end\nend\n")
  end

  # The files an app ends with after the block, from a fresh copy of the host
  # app that maquina:oauth has run on. Migration timestamps are normalized.
  def in_fresh_app
    prepare_destination
    write_host_app
    FileUtils.mkdir_p(File.join(destination_root, "app/models"))
    File.write(File.join(destination_root, "app/models/access_token.rb"), "class AccessToken < ApplicationRecord\nend\n")
    yield
    snapshot.to_h do |path, content|
      [path.gsub(/\d{14}/, "TIMESTAMP"), content.gsub(/\d{4}_\d{2}_\d{2}_\d{6}/, "VERSION")]
    end
  end

  def run_mcp_generator
    capture(:stdout) { Maquina::Generators::McpGenerator.start(["--quiet"], destination_root: destination_root) }
  end

  def snapshot
    Dir.glob("**/*", base: destination_root).sort
      .reject { |path| File.directory?(File.join(destination_root, path)) }
      .to_h { |path| [path, File.read(File.join(destination_root, path))] }
  end

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
