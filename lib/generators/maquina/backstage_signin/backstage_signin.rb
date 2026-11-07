module Maquina
  module Generators
    # Puts the backstage behind the app's own Clave sign-in instead of the
    # shared Basic Auth login. The dashboard generators (solid_errors,
    # mission_control_jobs, security) call install_backstage_signin after they
    # write their files, so whichever runs, and in whatever order, the backstage
    # ends up on the sign-in when Clave is installed.
    #
    # Who gets in is User#backstage_access?: an unblocked user whose email is
    # listed under backstage.emails in credentials. The same predicate gates
    # the admin-only MCP tools, which is why maquina:mcp calls
    # add_backstage_access_to_user too.
    #
    # Each step edits a snippet the generators wrote. One that is not found
    # (the app changed it) is left alone and named in backstage_signin_pending
    # for the post-install message.
    #
    # Every method is private: a public method on a generator is a Thor step.
    module BackstageSignin
      TEMPLATES = File.expand_path("templates", __dir__)

      USER_MODEL = "app/models/user.rb"
      BACKSTAGE_CONTROLLER = "app/controllers/backstage_controller.rb"
      DASHBOARD_CONTROLLER = "app/controllers/backstage_dashboard_controller.rb"
      SECURITY_CONTROLLER = "app/controllers/backstage/security_controller.rb"
      SOLID_ERRORS_INITIALIZER = "config/initializers/solid_errors.rb"
      MISSION_CONTROL_INITIALIZER = "config/initializers/mission_control.rb"
      ACCESS_TEST = "test/integration/backstage_access_test.rb"

      BACKSTAGE_CLASS = /^class BackstageController < ActionController::Base\n/
      CLASS_END = /^end\s*\z/
      BASIC_AUTH_ACTIONS = /\n  before_action :require_backstage_credentials\n  before_action :authenticate(_backstage)?\n/
      # The private section both controllers end with: nothing in it but the
      # Basic Auth helpers.
      DASHBOARD_BASIC_AUTH = /\n\n  private\n\n  # Closed \(503\) until credentials\.backstage is set\..*\n  end\n(?=end\n?\z)/m
      SECURITY_BASIC_AUTH = /\n\n  private\n\n  def authenticate\n.*\n  end\n(?=end\n?\z)/m
      SECURITY_HEADER = /# Rack::Attack's last week, read from the `security` database\. Behind the same\n.*\n.*so it is never left open\.\n/
      SOLID_ERRORS_BASIC_AUTH = /\n  backstage = Rails\.application\.credentials\.backstage \|\| \{\}\n\n  config\.solid_errors\.username = .*\n  config\.solid_errors\.password = .*\n/
      MISSION_CONTROL_BASIC_AUTH = /  backstage = Rails\.application\.credentials\.backstage \|\| \{\}\n\n  MissionControl::Jobs\.http_basic_auth_user = .*\n  MissionControl::Jobs\.http_basic_auth_password = .*\n/

      # The people the generated access test signs in as.
      USER_FIXTURES = {
        "backstage_operator" => {"email_address" => "backstage-operator@example.com", "name" => "Backstage Operator", "role" => "admin"},
        "backstage_member" => {"email_address" => "backstage-member@example.com", "name" => "Backstage Member", "role" => "admin"}
      }.freeze

      private

      def clave_installed?
        # EmailVerification is Clave's own. Rails' authentication generator
        # (maquina:registration) also writes the other two, but its User has no
        # blocked?, so that app keeps Basic Auth.
        [USER_MODEL, "app/models/email_verification.rb", "app/controllers/concerns/authentication.rb"]
          .all? { |path| backstage_file?(path) }
      end

      def backstage_signin_pending
        @backstage_signin_pending ||= []
      end

      # Returns true when the backstage is (now) behind the sign-in.
      def install_backstage_signin
        return false unless clave_installed?

        add_backstage_access_to_user
        convert_backstage_controller
        convert(DASHBOARD_CONTROLLER, done_unless: "require_backstage_credentials") do
          gsub_file DASHBOARD_CONTROLLER, BASIC_AUTH_ACTIONS, ""
          gsub_file DASHBOARD_CONTROLLER, DASHBOARD_BASIC_AUTH, "\n"
          gsub_file DASHBOARD_CONTROLLER, "under the same backstage Basic auth.", "behind the same backstage sign-in."
        end
        convert(SECURITY_CONTROLLER, done_unless: "require_backstage_credentials") do
          gsub_file SECURITY_CONTROLLER, BASIC_AUTH_ACTIONS, ""
          gsub_file SECURITY_CONTROLLER, SECURITY_BASIC_AUTH, "\n"
          gsub_file SECURITY_CONTROLLER, SECURITY_HEADER,
            "# Rack::Attack's last week, read from the `security` database. Behind the\n" \
            "# backstage sign-in, like every page BackstageController serves.\n"
        end
        convert(SOLID_ERRORS_INITIALIZER, done_unless: "config.solid_errors.password =") do
          gsub_file SOLID_ERRORS_INITIALIZER, SOLID_ERRORS_BASIC_AUTH,
            "\n  # Signed-in backstage users only, through BackstageController. Leave\n" \
            "  # username and password unset: a password turns Basic Auth back on.\n"
        end
        convert(MISSION_CONTROL_INITIALIZER, done_unless: "http_basic_auth_user") do
          gsub_file MISSION_CONTROL_INITIALIZER, MISSION_CONTROL_BASIC_AUTH,
            "  # Signed-in backstage users only, through BackstageController.\n" \
            "  MissionControl::Jobs.http_basic_auth_enabled = false\n"
        end
        create_backstage_access_test
        true
      end

      # User.backstage_emails and User#backstage_access?. Also called by
      # maquina:mcp, whose admin-only tools use the same gate.
      def add_backstage_access_to_user
        return unless backstage_file?(USER_MODEL)

        content = File.read(File.join(destination_root, USER_MODEL))
        return if content.include?("def backstage_access?")

        if content.match?(/^  private$/)
          inject_into_file USER_MODEL, backstage_access_methods, before: /^  private$/
        elsif content.match?(CLASS_END)
          inject_into_file USER_MODEL, "\n#{backstage_access_methods.chomp}", before: CLASS_END
        else
          backstage_signin_pending << USER_MODEL
        end
      end

      def convert_backstage_controller
        return unless backstage_file?(BACKSTAGE_CONTROLLER)

        content = File.read(File.join(destination_root, BACKSTAGE_CONTROLLER))
        return if content.include?("require_backstage_access")
        return backstage_signin_pending << BACKSTAGE_CONTROLLER unless content.match?(BACKSTAGE_CLASS) && content.match?(CLASS_END)

        inject_into_file BACKSTAGE_CONTROLLER, backstage_controller_header, after: BACKSTAGE_CLASS
        inject_into_file BACKSTAGE_CONTROLLER, backstage_controller_private, before: CLASS_END
      end

      # Runs the edits when the file still has Basic Auth (`done_unless`), then
      # checks they took. A file the app has reshaped keeps its Basic Auth and
      # is named in the post-install message.
      def convert(path, done_unless:)
        full_path = File.join(destination_root, path)
        return unless File.exist?(full_path)
        return unless File.read(full_path).include?(done_unless)

        yield
        backstage_signin_pending << path if File.read(full_path).include?(done_unless)
      end

      def create_backstage_access_test
        return unless backstage_file?("test/test_helpers/session_test_helper.rb")

        create_file ACCESS_TEST, File.read(File.join(TEMPLATES, ACCESS_TEST)) unless backstage_file?(ACCESS_TEST)
        append_backstage_fixture "test/fixtures/accounts.yml", "backstage", {"name" => "Backstage"}
        USER_FIXTURES.each do |label, attributes|
          append_backstage_fixture "test/fixtures/users.yml", label, attributes.merge("account" => "backstage")
        end
      end

      # Appends a fixture under its label unless the label is already there,
      # creating the file when it is missing.
      def append_backstage_fixture(path, label, attributes)
        entry = "#{label}:\n" + attributes.map { |key, value| "  #{key}: #{value}\n" }.join
        return create_file(path, entry) unless backstage_file?(path)

        content = File.read(File.join(destination_root, path))
        return if content.match?(/^#{Regexp.escape(label)}:/)

        separator = if content.empty?
          ""
        else
          (content.end_with?("\n") ? "\n" : "\n\n")
        end
        append_to_file path, separator + entry
      end

      def backstage_file?(path)
        File.exist?(File.join(destination_root, path))
      end

      def say_backstage_access
        say "  - Backstage access: signed-in users listed in credentials (bin/rails credentials:edit)"
        say "    backstage:"
        say "      emails:"
        say "        - you@example.com"
        say "    Anyone else gets a 404. Do not set backstage.username or password: Solid Errors"
        say "    turns its Basic Auth back on when a password is set."
      end

      def say_backstage_signin_pending
        return if backstage_signin_pending.empty?

        say ""
        say "These files were changed by hand, so they keep their Basic Auth. Move them to", :yellow
        say "the backstage sign-in yourself (BackstageController#require_backstage_access):"
        backstage_signin_pending.uniq.each { |path| say "  - #{path}" }
      end

      def backstage_access_methods
        <<-RUBY
  # Who may open the backstage and use the admin-only MCP tools: an unblocked
  # user whose email is listed in credentials (backstage.emails). An empty list
  # is nobody. A list in config.x.backstage_emails is used instead, even an
  # empty one; that is how the tests grant access. (Unset, config.x answers an
  # empty OrderedOptions, not nil.)
  def self.backstage_emails
    emails = Rails.configuration.x.backstage_emails
    emails = Rails.application.credentials.dig(:backstage, :emails) unless emails.is_a?(Array)
    Array(emails).map { |email| email.to_s.strip.downcase }
  end

  def backstage_access?
    !blocked? && self.class.backstage_emails.include?(email_address)
  end

        RUBY
      end

      def backstage_controller_header
        <<-RUBY
  # The app's sign-in rather than a shared Basic Auth password, for every
  # backstage page: the overview, Security and, through base_controller_class,
  # the Solid Errors and Mission Control Jobs engines. Who gets in is
  # User#backstage_access?; anyone else gets a 404, so the pages never confirm
  # they exist.
  include Authentication

  # After the include, so it runs behind require_authentication and can rely
  # on Current.session being resolved.
  before_action :require_backstage_access

        RUBY
      end

      def backstage_controller_private
        <<-RUBY

  private

  # ActiveRecord::RecordNotFound rather than a redirect with an alert: the
  # alert would confirm there is a backstage.
  def require_backstage_access
    raise ActiveRecord::RecordNotFound unless Current.user&.backstage_access?
  end

  # Restated rather than inherited: this controller serves two mounted
  # engines, and inside one a bare new_session_path generates against the
  # engine's routes. main_app reaches the app's sign-in from anywhere.
  #
  # 303 for PATCH/PUT/DELETE: both engines submit those verbs (resolve, retry,
  # discard), and Turbo keeps the verb through a 302, so an expired session on
  # Discard would re-issue the DELETE against the sign-in page.
  def request_authentication
    session[:return_to_after_authenticating] = request.url
    redirect_to main_app.new_session_path
    response.status = :see_other if request.patch? || request.put? || request.delete?
  end
        RUBY
      end
    end
  end
end
