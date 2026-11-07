require "test_helper"
require "generators/maquina/solid_errors/solid_errors_generator"
require "generators/maquina/mission_control_jobs/mission_control_jobs_generator"
require "generators/maquina/security/security_generator"
require "generators/maquina/mcp/mcp_generator"

# The dashboard generators put the backstage behind the app's Clave sign-in
# when Clave is installed (BackstageSignin), and keep the shared Basic Auth
# login when it is not.
class Maquina::Generators::BackstageSigninTest < Rails::Generators::TestCase
  tests Maquina::Generators::SolidErrorsGenerator
  destination File.expand_path("../../tmp", __dir__)

  USER_MODEL = <<~RUBY
    class User < ApplicationRecord
      belongs_to :account
      has_many :sessions, dependent: :destroy

      def blocked?
        blocked_at.present?
      end

      private

      def email_cannot_contain_plus
      end
    end
  RUBY

  setup do
    prepare_destination
    write_host_app
  end

  test "without Clave the backstage keeps its Basic Auth" do
    output = run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage_controller.rb" do |content|
      assert_no_match(/include Authentication|require_backstage_access/, content)
    end
    assert_file "app/controllers/backstage_dashboard_controller.rb", /authenticate_or_request_with_http_basic/
    assert_file "config/initializers/solid_errors.rb", /config\.solid_errors\.password = /
    assert_no_file "test/integration/backstage_access_test.rb"
    assert_match(/username: your_user/, output)
  end

  test "Rails' own authentication (maquina:registration) keeps Basic Auth" do
    write_clave
    FileUtils.rm(File.join(destination_root, "app/models/email_verification.rb"))

    run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage_controller.rb" do |content|
      assert_no_match(/include Authentication/, content)
    end
    assert_file "app/models/user.rb" do |content|
      assert_no_match(/backstage_access\?/, content)
    end
  end

  test "with Clave the backstage is behind the app's sign-in" do
    write_clave

    output = run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage_controller.rb" do |content|
      assert_match(/class BackstageController < ActionController::Base\n  # The app's sign-in/, content)
      assert_match(/  include Authentication\n\n.*\n.*\n  before_action :require_backstage_access\n/, content)
      assert_match(/helper SolidErrorsHelper/, content)
      assert_match(/raise ActiveRecord::RecordNotFound unless Current\.user&\.backstage_access\?/, content)
      assert_match(/redirect_to main_app\.new_session_path\n    response\.status = :see_other if request\.patch\? \|\| request\.put\? \|\| request\.delete\?/, content)
      assert RubyVM::InstructionSequence.compile(content)
    end
    assert_file "app/controllers/backstage_dashboard_controller.rb" do |content|
      assert_no_match(/http_basic|require_backstage_credentials|private/, content)
      assert_match(/behind the same backstage sign-in/, content)
      assert RubyVM::InstructionSequence.compile(content)
    end
    assert_file "config/initializers/solid_errors.rb" do |content|
      assert_no_match(/config\.solid_errors\.(username|password)/, content)
      assert_match(/a password turns Basic Auth back on/, content)
    end
    assert_file "app/models/user.rb" do |content|
      assert_match(/  def backstage_access\?\n    !blocked\? && self\.class\.backstage_emails\.include\?\(email_address\)\n  end\n\n  private\n/, content)
      assert_match(/Rails\.application\.credentials\.dig\(:backstage, :emails\)/, content)
      assert RubyVM::InstructionSequence.compile(content)
    end
    assert_file "test/integration/backstage_access_test.rb", /class BackstageAccessTest < ActionDispatch::IntegrationTest/
    assert_file "test/fixtures/users.yml" do |content|
      assert_match(/^backstage_operator:\n  email_address: backstage-operator@example\.com\n/, content)
      assert_match(/^backstage_member:\n/, content)
    end
    assert_file "test/fixtures/accounts.yml", /^backstage:\n  name: Backstage\n/
    assert_match(/emails:\n\s+- you@example\.com/, output)
    assert_no_match(/username: your_user/, output)
  end

  test "Mission Control Jobs and Security convert their files too" do
    write_clave

    run_generator %w[--prefix /admin]
    run_sibling Maquina::Generators::MissionControlJobsGenerator
    run_sibling Maquina::Generators::SecurityGenerator

    assert_file "config/initializers/mission_control.rb" do |content|
      assert_no_match(/http_basic_auth_(user|password)/, content)
      assert_match(/MissionControl::Jobs\.http_basic_auth_enabled = false/, content)
    end
    assert_file "app/controllers/backstage/security_controller.rb" do |content|
      assert_no_match(/http_basic|require_backstage_credentials|def authenticate/, content)
      assert_match(/Behind the\n# backstage sign-in/, content)
      assert RubyVM::InstructionSequence.compile(content)
    end
    assert_file "app/controllers/backstage_controller.rb" do |content|
      assert_equal 1, content.scan("include Authentication").size
      assert_equal 1, content.scan("def require_backstage_access").size
    end
    assert_file "app/models/user.rb" do |content|
      assert_equal 1, content.scan("def backstage_access?").size
    end
    assert_file "test/fixtures/users.yml" do |content|
      assert_equal 1, content.scan(/^backstage_operator:/).size
    end
  end

  test "running a dashboard generator again changes nothing" do
    write_clave

    run_generator %w[--prefix /admin]
    first = snapshot
    run_generator %w[--prefix /admin]

    assert_equal first, snapshot
  end

  test "a file changed by hand keeps its Basic Auth and is named" do
    write_clave
    mkdir_p("app/controllers")
    File.write(File.join(destination_root, "app/controllers/backstage_dashboard_controller.rb"), <<~RUBY)
      class BackstageDashboardController < BackstageController
        before_action :require_backstage_credentials, :check_ip

        def index
        end
      end
    RUBY

    output = run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage_dashboard_controller.rb", /before_action :require_backstage_credentials, :check_ip/
    assert_match(%r{keep their Basic Auth.*\n.*\n  - app/controllers/backstage_dashboard_controller\.rb}, output)
  end

  test "a user model without a private section gets the methods before its end" do
    write_clave(user: "class User < ApplicationRecord\n  def blocked? = false\nend\n")

    run_generator %w[--prefix /admin]

    assert_file "app/models/user.rb" do |content|
      assert_match(/def blocked\? = false\n\n  # Who may open the backstage/, content)
      assert_match(/  def backstage_access\?\n.*\n  end\nend\n\z/, content)
      assert RubyVM::InstructionSequence.compile(content)
    end
  end

  test "maquina:mcp gives the user the same backstage access its admin tools check" do
    write_clave
    File.write(File.join(destination_root, "app/models/access_token.rb"), "class AccessToken < ApplicationRecord\nend\n")

    output = capture(:stdout) { Maquina::Generators::McpGenerator.start([], destination_root: destination_root) }

    assert_file "app/models/user.rb", /def backstage_access\?/
    assert_file "app/models/mcp/tool_definitions.rb", /user\.backstage_access\? && Mcp\.enabled_for\?\(user\)/
    assert_file "test/test_helpers/mcp_test_helper.rb", /Rails\.configuration\.x\.backstage_emails = MCP_BACKSTAGE_EMAILS\.dup/
    assert_match(/An account's admin role is not enough/, output)
  end

  private

  def write_host_app
    mkdir_p("config")
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
    File.write(File.join(destination_root, "Gemfile"), "source \"https://rubygems.org\"\n")
  end

  def write_clave(user: USER_MODEL)
    mkdir_p("app/models")
    mkdir_p("app/controllers/concerns")
    mkdir_p("test/test_helpers")
    File.write(File.join(destination_root, "app/models/user.rb"), user)
    File.write(File.join(destination_root, "app/models/email_verification.rb"), "class EmailVerification < ApplicationRecord\nend\n")
    File.write(File.join(destination_root, "app/controllers/concerns/authentication.rb"), "module Authentication\nend\n")
    File.write(File.join(destination_root, "test/test_helpers/session_test_helper.rb"), "module SessionTestHelper\nend\n")
  end

  def run_sibling(generator)
    capture(:stdout) { generator.start(%w[--prefix /admin], destination_root: destination_root) }
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
