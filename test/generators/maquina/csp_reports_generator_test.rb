require "test_helper"
require "generators/maquina/csp_reports/csp_reports_generator"

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
    write "config/routes.rb", "Rails.application.routes.draw do\nend\n"
    write "db/security_schema.rb", SECURITY_SCHEMA
    write "config/initializers/content_security_policy.rb", CSP_INITIALIZER
    write "config/initializers/rack_attack.rb", RACK_ATTACK
    write "config/recurring.yml", "production:\n  purge_abuse_events:\n    command: \"x\"\n"
    write "app/views/backstage/security/show.html.erb", SECURITY_PAGE
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

  private

  def write(path, content)
    full = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end
end
