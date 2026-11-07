require "test_helper"
require "generators/maquina/csp_reports/csp_reports_generator"
require "generators/maquina/mcp/mcp_generator"

class Maquina::Generators::CspReportsGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::CspReportsGenerator
  destination File.expand_path("../../tmp", __dir__)

  SECURITY_SCHEMA = <<~RUBY
    # The `security` database.

    ActiveRecord::Schema[8.1].define(version: 1) do
      create_table "abuse_events", force: :cascade do |t|
        t.string "ip", null: false
      end
    end
  RUBY

  CSP_INITIALIZER = <<~RUBY
    Rails.application.configure do
      config.content_security_policy do |policy|
        policy.default_src :self
      end

      config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
      config.content_security_policy_report_only = true
    end
  RUBY

  RACK_ATTACK = <<~RUBY
    class Rack::Attack
      def self.counted_ip(req)
        req.ip unless req.path.start_with?("/assets", "/rails/active_storage")
      end
    end
  RUBY

  SECURITY_PAGE = <<~ERB
    <div class="py-8 space-y-8">
      <% if @report.empty? %>
        empty
      <% end %>
    </div>
  ERB

  setup do
    prepare_destination
    write_host_app
  end

  test "refuses to run without the security database" do
    File.delete(File.join(destination_root, "db/security_schema.rb"))

    output = capture(:stderr) { run_generator }

    assert_match(/Run `rails g maquina:security --prefix \/admin` first/, output)
    assert_no_file "app/controllers/csp_reports_controller.rb"
  end

  test "installs the endpoint, the models and the route" do
    run_generator

    assert_file "app/controllers/csp_reports_controller.rb", /class CspReportsController < ActionController::API/
    assert_file "app/models/security/csp_violation.rb", /class Security::CspViolation < Security::Record/
    assert_file "app/models/security/csp_violation_report.rb", /class Security::CspViolationReport/
    assert_file "config/routes.rb", %r{post "/csp-reports", to: "csp_reports#create", as: :csp_reports}
  end

  test "adds the table as a security migration and to the schema" do
    run_generator

    assert_migration "db/security_migrate/create_csp_violations.rb", /create_table :csp_violations/
    migration = Dir[File.join(destination_root, "db/security_migrate/*_create_csp_violations.rb")].first
    version = File.basename(migration).split("_").first
    assert_file "db/security_schema.rb" do |content|
      assert_match(/define\(version: #{version.sub(/\A(\d{4})(\d{2})(\d{2})(\d{6})\z/, '\1_\2_\3_\4')}\)/, content)
      assert_match(/create_table "abuse_events".*create_table "csp_violations"/m, content)
      assert_match(/\n  end\nend\n\z/, content)
      assert_no_match(/[ \t]+$/, content, "no trailing whitespace")
    end
  end

  test "points the policy at the endpoint and gives anonymous requests a nonce" do
    run_generator %w[--path /security/csp]

    assert_file "config/initializers/content_security_policy.rb" do |content|
      assert_match(%r{config\.content_security_policy do \|policy\|\n.*policy\.report_uri "/security/csp"}m, content)
      assert_no_match(/report_to/, content.gsub(/#.*$/, ""))
      assert_match(/request\.session\.id\.to_s\.presence \|\| SecureRandom\.base64\(16\)/, content)
    end
  end

  test "takes the endpoint out of the general throttle and caps it on its own" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(%r{start_with\?\("/assets", "/rails/active_storage", "/csp-reports"\)}, content)
      assert_match(/Rack::Attack\.throttle\("csp\/ip", limit: 100, period: 5\.minutes\)/, content)
    end
  end

  test "extends a STATIC_FILE_PREFIXES list when the rules use one" do
    write "config/initializers/rack_attack.rb", "class Rack::Attack\n  STATIC_FILE_PREFIXES = %w[/assets /u/].freeze\nend\n"

    run_generator

    assert_file "config/initializers/rack_attack.rb", %r{STATIC_FILE_PREFIXES = %w\[/assets /u/ /csp-reports\]}
  end

  test "purges daily and shows the section on the Security page" do
    run_generator

    assert_file "config/recurring.yml", /purge_csp_violations:\n    command: "Security::CspViolation\.expired\.delete_all"/
    assert_file "app/views/backstage/security/_csp_violations.html.erb", /Content Security Policy violations/
    assert_file "app/views/backstage/security/show.html.erb",
      %r{<% end %>\n\n  <%= render "backstage/security/csp_violations", report: Security::CspViolationReport\.new %>\n</div>\n\z}
  end

  test "running twice changes nothing the second time" do
    run_generator
    snapshot = %w[db/security_schema.rb config/initializers/rack_attack.rb config/initializers/content_security_policy.rb
      config/recurring.yml app/views/backstage/security/show.html.erb config/routes.rb].to_h { |f| [f, File.read(File.join(destination_root, f))] }

    run_generator

    snapshot.each { |file, content| assert_equal content, File.read(File.join(destination_root, file)), file }
    assert_equal 1, Dir[File.join(destination_root, "db/security_migrate/*_create_csp_violations.rb")].size
  end

  test "lists what it could not place instead of forcing it" do
    write "config/initializers/content_security_policy.rb", "# Rails.application.configure do\n# end\n"
    write "config/initializers/rack_attack.rb", "class Rack::Attack\nend\n"

    output = run_generator

    assert_match(%r{policy\.report_uri "/csp-reports"}, output)
    assert_match(/Exempt \/csp-reports from the general throttle/, output)
  end

  test "writes nothing about MCP without maquina:mcp" do
    output = run_generator []

    assert_no_file "app/models/mcp/tools/csp_reports.rb"
    assert_no_file "test/models/mcp/tools/csp_reports_test.rb"
    assert_no_match(/mcp/i, output)
  end

  test "installs the read-only admin MCP tools when maquina:mcp is present" do
    write_mcp_registry

    output = run_generator []

    assert_file "app/models/mcp/tools/csp_reports.rb" do |content|
      assert_match(/module Mcp\n  module Tools\n    module CspReports\n/, content)
      assert_match(/ADMIN_ONLY = true/, content)
      assert_match(/WRITE_TOOLS = %w\[\]\.freeze/, content)
      %w[list_csp_reports csp_report_summary].each do |tool|
        assert_match(/name: "#{tool}"/, content)
        assert_match(/def self\.#{tool}\(scope:/, content)
      end
      assert_match(/::Security::CspViolationReport\.new/, content)
      assert_no_match(/readOnlyHint: false/, content)
    end
    assert_file "test/models/mcp/tools/csp_reports_test.rb" do |content|
      assert_match(/users\(:mcp_member\)/, content)
      assert_match(/-32602/, content)
    end
    assert_match(%r{app/models/mcp/tools/csp_reports\.rb}, output)
  end

  test "generated MCP files are valid Ruby" do
    write_mcp_registry

    run_generator []

    %w[app/models/mcp/tools/csp_reports.rb test/models/mcp/tools/csp_reports_test.rb].each do |path|
      assert RubyVM::InstructionSequence.compile(File.read(File.join(destination_root, path)))
    end
  end

  test "keeps an existing MCP tool file" do
    write_mcp_registry
    FileUtils.mkdir_p(File.join(destination_root, "app/models/mcp/tools"))
    File.write(File.join(destination_root, "app/models/mcp/tools/csp_reports.rb"), "# custom tools\n")

    run_generator []

    assert_file "app/models/mcp/tools/csp_reports.rb", "# custom tools\n"
  end

  test "running twice with maquina:mcp changes nothing the second time" do
    write_mcp_registry

    run_generator []
    first = snapshot
    run_generator []

    assert_equal first, snapshot
  end

  test "running before or after maquina:mcp ends in the same files" do
    sibling_first = in_fresh_app do
      run_generator []
      run_mcp_generator
    end
    mcp_first = in_fresh_app do
      run_mcp_generator
      run_generator []
    end

    assert sibling_first.key?("app/models/mcp/tools/csp_reports.rb")
    assert sibling_first.key?("test/models/mcp/tools/csp_reports_test.rb")
    # Both generators add routes at the top of the draw block, so only the
    # order of the routes depends on which ran first.
    assert_equal sibling_first.delete("config/routes.rb").to_s.lines.sort, mcp_first.delete("config/routes.rb").to_s.lines.sort
    assert_equal sibling_first, mcp_first
  end

  test "maquina:mcp leaves out the CSP tools until the schema has csp_violations" do
    in_fresh_app { run_mcp_generator }

    assert_no_file "app/models/mcp/tools/csp_reports.rb"
  end

  private

  def write_host_app
    write "config/routes.rb", "Rails.application.routes.draw do\nend\n"
    write "db/security_schema.rb", SECURITY_SCHEMA
    write "config/initializers/content_security_policy.rb", CSP_INITIALIZER
    write "config/initializers/rack_attack.rb", RACK_ATTACK
    write "config/recurring.yml", "production:\n  purge_abuse_events:\n    command: \"x\"\n"
    write "app/views/backstage/security/show.html.erb", SECURITY_PAGE
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

  def write(path, content)
    full = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end
end
