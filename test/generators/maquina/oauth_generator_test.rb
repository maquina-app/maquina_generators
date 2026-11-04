require "test_helper"
require "generators/maquina/oauth/oauth_generator"

class Maquina::Generators::OauthGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::OauthGenerator
  destination File.expand_path("../../tmp", __dir__)

  CLAVE_USER = File.expand_path("../../../lib/generators/maquina/clave/templates/app/models/user.rb.tt", __dir__)
  RACK_ATTACK_TEMPLATE = File.expand_path("../../../lib/generators/maquina/rack_attack/templates/config/initializers/rack_attack.rb.tt", __dir__)

  TEST_HELPER = <<~RUBY
    ENV["RAILS_ENV"] ||= "test"
    require_relative "../config/environment"
    require "rails/test_help"
  RUBY

  FILTER_PARAMETERS = <<~RUBY
    Rails.application.config.filter_parameters += [
      :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
    ]
  RUBY

  setup do
    prepare_destination
    write "config/routes.rb", "Rails.application.routes.draw do\nend\n"
    write "app/models/email_verification.rb", "class EmailVerification < ApplicationRecord\nend\n"
    write "app/controllers/concerns/authentication.rb", "module Authentication\nend\n"
    # The User model clave generates, as clave generates it.
    write "app/models/user.rb", File.read(CLAVE_USER)
    write "config/initializers/rack_attack.rb", rack_attack_initializer
    write "config/initializers/filter_parameter_logging.rb", FILTER_PARAMETERS
    write "test/test_helper.rb", TEST_HELPER
  end

  test "refuses to run without clave" do
    File.delete(File.join(destination_root, "app/models/email_verification.rb"))

    output = capture(:stderr) { run_generator }

    assert_match(/maquina:oauth signs people in through Clave\. Run `rails g maquina:clave` first\./, output)
    assert_no_file "app/models/access_token.rb"
    assert_file "config/routes.rb", "Rails.application.routes.draw do\nend\n"
  end

  test "refuses a flag that is not a plain name before changing anything" do
    output = capture(:stderr) { run_generator %w[--flag Beta-MCP] }

    assert_match(/--flag takes a lowercase name/, output)
    assert_no_file "app/models/mcp.rb"
  end

  test "creates the three migrations" do
    run_generator

    assert_migration "db/migrate/create_oauth_clients.rb" do |content|
      assert_match(/t\.string :client_id, null: false/, content)
      assert_match(/t\.string :client_name, null: false/, content)
      assert_match(/t\.text :redirect_uris, null: false/, content)
      assert_match(/t\.datetime :metadata_fetched_at, null: false/, content)
      assert_match(/add_index :oauth_clients, :client_id, unique: true/, content)
      assert_match(/ActiveRecord::Migration\[\d+\.\d+\]/, content)
    end
    assert_migration "db/migrate/create_oauth_authorization_codes.rb" do |content|
      %w[code_digest code_challenge redirect_uri scope resource].each do |column|
        assert_match(/t\.string :#{column}, null: false/, content)
      end
      assert_match(/t\.datetime :expires_at, null: false/, content)
      assert_match(/t\.datetime :used_at$/, content)
      assert_match(/add_index :oauth_authorization_codes, :code_digest, unique: true/, content)
    end
    assert_migration "db/migrate/create_access_tokens.rb" do |content|
      assert_match(/t\.references :user, null: false, foreign_key: true/, content)
      assert_match(/t\.references :oauth_client, null: false, foreign_key: true/, content)
      assert_match(/add_index :access_tokens, :token_digest, unique: true/, content)
      assert_match(/add_index :access_tokens, :refresh_token_digest, unique: true/, content)
      assert_match(/t\.datetime :revoked_at$/, content)
      assert_no_match(/refresh_token_expires/, content)
    end
  end

  test "creates the models" do
    run_generator

    assert_file "app/models/oauth_client.rb" do |content|
      assert_match(/METADATA_TTL = 24\.hours/, content)
      assert_match(/serialize :redirect_uris, coder: JSON/, content)
      assert_match(/def self\.from_metadata!\(client_id\)/, content)
      assert_match(/MetadataFetcher\.fetch\(client_id\)/, content)
      assert_match(/rescue ActiveRecord::RecordNotUnique\n.*\n.*\n.*\n    find_by!\(client_id: client_id\)/, content)
      assert_match(/errors\.of_kind\?\(:client_id, :taken\)/, content)
    end
    assert_file "app/models/oauth_client/metadata_fetcher.rb" do |content|
      assert_match(/MAX_BYTES = 16_384/, content)
      assert_match(/TIMEOUT = 3$/, content)
      assert_match(/DNS rebinding/, content)
      assert_no_match(/require "(rails|active_)|ActiveSupport|Rails\.\w/, content)
    end
    assert_file "app/models/oauth_authorization_code.rb" do |content|
      assert_match(/TTL = 10\.minutes/, content)
      assert_match(/def self\.redeem!\(raw, client:, redirect_uri:, verifier:\)/, content)
      assert_match(/Base64\.urlsafe_encode64\(Digest::SHA256\.digest\(verifier\), padding: false\)/, content)
    end
    assert_file "app/models/access_token.rb" do |content|
      assert_match(/ACCESS_TTL = 1\.hour/, content)
      assert_match(/SCOPES = %w\[read write\]\.freeze/, content)
      assert_match(/def self\.issue!\(user:, client:, scope:, resource:\)/, content)
      assert_match(/def self\.authenticate\(raw\)/, content)
      assert_match(/def rotate!\(client:\)/, content)
      assert_match(/Digest::SHA256\.hexdigest/, content)
    end
    assert_file "app/models/connected_application.rb" do |content|
      assert_match(/class ConnectedApplication$/, content)
      assert_match(/def self\.for\(user\)/, content)
      assert_match(/def revoke!/, content)
    end
  end

  test "a person's grants go with them" do
    run_generator
    run_generator

    assert_file "app/models/user.rb" do |content|
      assert_match(/has_many :sessions, dependent: :destroy\n  has_many :access_tokens, dependent: :delete_all\n  has_many :oauth_authorization_codes, dependent: :delete_all\n\n/, content)
      assert_equal 1, content.scan("has_many :access_tokens").size
    end
  end

  test "writes the MCP gate without a flag" do
    run_generator

    assert_file "app/models/mcp.rb" do |content|
      assert_match(/PROTOCOL_VERSION = "2026-07-28"/, content)
      assert_match(/SERVER_VERSION = "0\.1\.0"/, content)
      assert_match(/^  FLAG = nil$/, content)
      assert_match(/def self\.enabled_for\?\(user\)\n    return true if FLAG\.nil\?/, content)
      assert_match(/The app owns this\s+# method/, content)
    end
  end

  test "flag gates MCP on credentials, then ENV" do
    run_generator %w[--flag beta_mcp]

    assert_file "app/models/mcp.rb" do |content|
      assert_match(/^  FLAG = :beta_mcp$/, content)
      assert_match(/credentials\.dig\(:features, FLAG\) \|\| ENV\[FLAG\.to_s\.upcase\]/, content)
      assert_match(/ActiveModel::Type::Boolean\.new\.cast/, content)
    end
    assert_file "test/test_helpers/oauth_test_helper.rb" do |content|
      assert_match(/^ENV\["BETA_MCP"\] = "true"$/, content)
      assert_match(/def with_mcp_flag\(enabled\)/, content)
    end
    assert_file "test/integration/oauth_authorization_test.rb", /with the beta_mcp flag off, the client gets access_denied/
    assert_file "test/integration/connected_applications_test.rb", /with the beta_mcp flag off, the page is not found/
  end

  test "without a flag the tests do not toggle one" do
    run_generator

    assert_file "test/test_helpers/oauth_test_helper.rb" do |content|
      assert_no_match(/ENV\[/, content)
      assert_no_match(/with_mcp_flag/, content)
    end
    assert_file "test/integration/oauth_authorization_test.rb" do |content|
      assert_no_match(/flag off/, content)
    end
  end

  test "keeps an app-owned gate and sets an unchanged FLAG line" do
    write "app/models/mcp.rb", "module Mcp\n  FLAG = nil\n\n  def self.enabled_for?(user) = user.admin?\nend\n"

    run_generator %w[--flag beta_mcp]

    assert_file "app/models/mcp.rb", "module Mcp\n  FLAG = :beta_mcp\n\n  def self.enabled_for?(user) = user.admin?\nend\n"
  end

  test "lists a FLAG line it cannot find" do
    write "app/models/mcp.rb", "module Mcp\n  def self.enabled_for?(user) = true\nend\n"

    output = run_generator %w[--flag beta_mcp]

    assert_match(/no longer has the generated FLAG line.*FLAG = :beta_mcp/m, output)
    assert_file "app/models/mcp.rb", "module Mcp\n  def self.enabled_for?(user) = true\nend\n"
  end

  test "creates the controllers" do
    run_generator

    assert_file "app/controllers/oauth/authorization_servers_controller.rb" do |content|
      assert_match(/< ActionController::API/, content)
      assert_match(/expires_in 1\.hour, public: true/, content)
      assert_match(/client_id_metadata_document_supported: true/, content)
      assert_match(/authorization_response_iss_parameter_supported: true/, content)
      assert_no_match(/registration_endpoint:|"offline_access"/, content)
    end
    assert_file "app/controllers/oauth/protected_resources_controller.rb" do |content|
      assert_match(/resource: "\#\{request\.base_url\}\/mcp"/, content)
      assert_match(/bearer_methods_supported: \["header"\]/, content)
    end
    assert_file "app/controllers/oauth/authorizations_controller.rb" do |content|
      assert_match(/class Oauth::AuthorizationsController < ApplicationController/, content)
      assert_match(/params\[:code_challenge_method\] != "S256"/, content)
      assert_match(/Mcp\.enabled_for\?\(Current\.user\)/, content)
      assert_match(/render :error, status: :bad_request/, content)
      assert_match(/iss: request\.base_url/, content)
    end
    assert_file "app/controllers/oauth/tokens_controller.rb" do |content|
      assert_match(/< ActionController::API/, content)
      assert_match(/before_action :no_store/, content)
      %w[invalid_request invalid_grant unsupported_grant_type invalid_target].each { |error| assert_match(/"#{error}"/, content) }
    end
    assert_file "app/controllers/oauth/revocations_controller.rb", /head :ok/
    assert_file "app/controllers/connected_applications_controller.rb" do |content|
      assert_match(/ConnectedApplication\.find\(Current\.user, params\[:id\]\)/, content)
      assert_match(/head :not_found unless Mcp\.enabled_for\?\(Current\.user\)/, content)
      assert_match(/status: :see_other/, content)
    end
  end

  test "no generated file logs a raw secret" do
    run_generator

    Dir.glob(File.join(destination_root, "app/**/*.rb")).each do |path|
      File.read(path).scan(/Rails\.logger\.\w+ .*$/).each do |line|
        assert_no_match(/\#\{(raw|code|access_token|refresh_token|params\[:(code|token|refresh_token|code_verifier)\])\}/, line, path)
      end
    end
  end

  test "generated code is standalone" do
    run_generator

    Dir.glob(File.join(destination_root, "{app,config,test}/**/*.{rb,erb,yml}")).each do |path|
      assert_no_match(/maquina_generators|require "mcp"|rack-cors|json_schemer/, File.read(path), path)
    end
  end

  test "adds the routes under the marker" do
    run_generator

    assert_file "config/routes.rb" do |content|
      assert_match(/# OAuth \(generated by maquina:oauth\)/, content)
      assert_match(%r{get "/\.well-known/oauth-authorization-server", to: "oauth/authorization_servers#show"}, content)
      assert_match(%r{get "/\.well-known/oauth-protected-resource/mcp", to: "oauth/protected_resources#show"}, content)
      assert_match(%r{get "/oauth/authorize", to: "oauth/authorizations#new", as: :new_oauth_authorization}, content)
      assert_match(%r{post "/oauth/authorize", to: "oauth/authorizations#create", as: :oauth_authorization}, content)
      assert_match(%r{post "/oauth/token", to: "oauth/tokens#create", as: :oauth_token}, content)
      assert_match(%r{post "/oauth/revoke", to: "oauth/revocations#create", as: :oauth_revocation}, content)
      assert_match(%r{  scope "/settings" do\n    resources :connected_apps, only: \[:index, :destroy\], controller: "connected_applications"\n  end\n}, content)
    end
  end

  test "prefix moves Connected apps" do
    run_generator %w[--prefix /account/]

    assert_file "config/routes.rb", %r{scope "/account" do\n    resources :connected_apps}
  end

  test "an empty prefix puts Connected apps at the root" do
    run_generator ["--prefix", "/"]

    assert_file "config/routes.rb" do |content|
      assert_no_match(/scope "/, content)
      assert_match(/^  resources :connected_apps, only: \[:index, :destroy\]/, content)
    end
  end

  test "creates the views" do
    run_generator

    assert_file "app/views/oauth/authorizations/new.html.erb" do |content|
      assert_match(/flex flex-1 items-center justify-center px-4 py-8/, content)
      assert_match(/bg-card rounded-xl shadow-sm border border-border p-8/, content)
      assert_match(/t\("\.title", client_name: @client\.client_name\)/, content)
      assert_match(/@client\.host/, content)
      assert_match(/data: \{ turbo: false \}/, content)
      assert_match(/name: "decision", value: "allow",\n\s+data: \{ component: "button", variant: "primary" \}/, content)
      assert_match(/name: "decision", value: "deny",\n\s+data: \{ component: "button", variant: "ghost" \}/, content)
      assert_match(/hidden_field_tag name, value/, content)
    end
    assert_file "app/views/oauth/authorizations/error.html.erb", /t\("\.title"\)/
    assert_file "app/views/connected_applications/index.html.erb" do |content|
      assert_match(/max-w-2xl/, content)
      assert_match(/bg-card rounded-xl border border-border divide-y/, content)
      assert_match(/data-component="badge"/, content)
      assert_match(/turbo_confirm: t\("\.revoke_confirm"/, content)
      assert_match(/text-destructive hover:bg-destructive\/10/, content)
      assert_match(/connected_app_path\(client\)/, content)
    end
  end

  test "skip-views leaves the views out and says which to write" do
    output = run_generator %w[--skip-views]

    assert_no_file "app/views/oauth/authorizations/new.html.erb"
    assert_no_file "app/views/connected_applications/index.html.erb"
    assert_file "app/controllers/connected_applications_controller.rb"
    assert_file "config/locales/oauth.en.yml"
    assert_match(/Write the views yourself/, output)
    # The suite stays green: tests that render a page are left out.
    assert_file "test/integration/oauth_authorization_test.rb" do |content|
      assert_no_match(/assert_select|shows who is asking|gets a page, not a redirect/, content)
      assert_match(/test "a signed-out visitor comes back to the exact authorize URL"/, content)
      assert_match(/test "refuses a plain PKCE challenge"/, content)
    end
    assert_file "test/integration/connected_applications_test.rb" do |content|
      assert_no_match(/assert_select|lists the apps/, content)
      assert_match(/test "another person's client is not found"/, content)
    end
  end

  test "views read every string from the locales" do
    run_generator

    en = YAML.load_file(File.join(destination_root, "config/locales/oauth.en.yml"))["en"]
    es = YAML.load_file(File.join(destination_root, "config/locales/oauth.es.yml"))["es"]
    assert_equal keys(en), keys(es)
    assert_equal "Allow %{client_name} to use your account?", en.dig("oauth", "authorizations", "new", "title")
    assert_equal "This app can't connect", en.dig("oauth", "authorizations", "error", "title")
    assert_equal "No apps are connected to your account.", en.dig("connected_applications", "index", "empty")

    {"oauth/authorizations/new" => en.dig("oauth", "authorizations", "new"),
     "oauth/authorizations/error" => en.dig("oauth", "authorizations", "error"),
     "connected_applications/index" => en.dig("connected_applications", "index")}.each do |view, locale|
      content = File.read(File.join(destination_root, "app/views/#{view}.html.erb"))
      content.scan(/t\("\.([a-z_]+)/).flatten.each { |key| assert locale.key?(key), "#{view}: .#{key}" }
    end
  end

  test "keeps codes and verifiers out of the logs" do
    run_generator

    assert_file "config/initializers/filter_parameter_logging.rb" do |content|
      assert content.start_with?(FILTER_PARAMETERS)
      assert_match(%r{filter_parameters \+= \[:token, /\\Acode\\z/, :code_verifier\]}, content)
    end
  end

  test "creates the fixtures and the people they sign in as" do
    run_generator

    assert_file "test/fixtures/oauth_clients.yml" do |content|
      assert_match(%r{client_id: https://inspector\.example\.com/oauth/client\.json}, content)
      assert_match(/client_name: MCP Inspector/, content)
      assert_match(%r{redirect_uris: '\["http://localhost:6274/oauth/callback"\]'}, content)
      assert_match(/metadata_fetched_at: <%= Time\.current %>/, content)
    end
    assert_file "test/fixtures/access_tokens.yml", /token_digest: <%= Digest::SHA256\.hexdigest\("mcp-member-read-access-token"\) %>/
    assert_file "test/fixtures/oauth_authorization_codes.yml", /code_digest: <%= Digest::SHA256\.hexdigest\("mcp-member-authorization-code"\) %>/
    assert_file "test/fixtures/accounts.yml", /^mcp:\n  name: MCP\n/
    assert_file "test/fixtures/users.yml" do |content|
      assert_match(/^mcp_member:\n  email_address: mcp-member@example\.com\n  name: MCP Member\n  role: member\n  account: mcp\n/, content)
      assert_match(/^mcp_admin:\n.*\n.*\n  role: admin\n/, content)
      assert_match(/^mcp_other:\n/, content)
    end
  end

  test "the helper's raw values match the fixtures' digests" do
    run_generator

    helper = File.read(File.join(destination_root, "test/test_helpers/oauth_test_helper.rb"))
    fixtures = File.read(File.join(destination_root, "test/fixtures/access_tokens.yml")) +
      File.read(File.join(destination_root, "test/fixtures/oauth_authorization_codes.yml"))
    raw_values = helper.scan(/^  [A-Z_]+(?:TOKEN|CODE|VERIFIER) = "([^"]+)"/).flatten

    assert_equal 12, raw_values.size
    raw_values.each { |raw| assert_includes fixtures, %("#{raw}"), raw }
  end

  test "appends fixtures only under missing labels" do
    write "test/fixtures/users.yml", "one:\n  email_address: one@example.com\n  account: one\nmcp_admin:\n  email_address: mine@example.com"
    write "test/fixtures/accounts.yml", "one:\n  name: One\n"

    run_generator

    assert_file "test/fixtures/users.yml" do |content|
      assert content.start_with?("one:\n  email_address: one@example.com\n  account: one\nmcp_admin:\n  email_address: mine@example.com\n\nmcp_member:\n")
      assert_equal 1, content.scan(/^mcp_admin:/).size
      assert_match(/^mcp_other:/, content)
    end
    assert_file "test/fixtures/accounts.yml", "one:\n  name: One\n\nmcp:\n  name: MCP\n"
  end

  test "loads the test helper and writes the tests" do
    run_generator

    assert_file "test/test_helper.rb", /require "rails\/test_help"\nrequire_relative "test_helpers\/oauth_test_helper"\n/
    assert_file "test/test_helpers/oauth_test_helper.rb" do |content|
      assert_match(/module OauthTestHelper/, content)
      assert_match(/def pkce_pair/, content)
      assert_match(/ActiveSupport\.on_load\(:active_support_test_case\) do\n  include OauthTestHelper\nend/, content)
    end
    assert_file "test/models/oauth_authorization_code_test.rb" do |content|
      assert_match(/test "redeems once"/, content)
      assert_match(/test "expires after ten minutes"/, content)
    end
    assert_file "test/models/access_token_test.rb", /test "a refresh token is bound to its client"/
    assert_file "test/models/connected_application_test.rb", /test "revoking stops every token and drops unused codes"/
    assert_file "test/integration/oauth_discovery_test.rb", /registration_endpoint/
    assert_file "test/integration/oauth_authorization_test.rb" do |content|
      assert_match(/test "refuses a plain PKCE challenge"/, content)
      assert_match(/test "a signed-out visitor comes back to the exact authorize URL"/, content)
      assert_match(/session\[:return_to_after_authenticating\]/, content)
      assert_match(/test "refuses another resource"/, content)
      assert_match(/redirect_params\["iss"\]/, content)
    end
    assert_file "test/integration/oauth_tokens_test.rb" do |content|
      assert_match(/test "a code works once"/, content)
      assert_match(/test "an expired code is refused"/, content)
      assert_match(/test "a refresh token works once"/, content)
      assert_match(/test "a refresh token sent by another client is refused"/, content)
      assert_match(/test "revoking an unknown token answers 200"/, content)
    end
    assert_file "test/integration/connected_applications_test.rb", /test "another person's client is not found"/
  end

  test "generated Ruby parses" do
    run_generator %w[--flag beta_mcp]

    Dir.glob(File.join(destination_root, "{app,test,config}/**/*.rb")).each do |path|
      assert RubyVM::InstructionSequence.compile_file(path), path
    end
  end

  test "takes /mcp and /oauth/token out of the per-IP count and throttles token requests" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(%r{req\.ip unless req\.path\.start_with\?\("/assets", "/rails/active_storage", "/mcp", "/oauth/token"\)}, content)
      assert_match(%r{Rack::Attack\.throttle\("oauth/token/client", limit: 30, period: 1\.minute\) do \|req\|\n  req\.params\["client_id"\]\.presence if req\.path == "/oauth/token" && req\.post\?\nend}, content)
    end
  end

  test "keeps the csp_reports exemption when both are installed" do
    write "config/initializers/rack_attack.rb", rack_attack_initializer.sub(%(start_with?("/assets", "/rails/active_storage")), %(start_with?("/assets", "/rails/active_storage", "/csp-reports")))

    run_generator

    assert_file "config/initializers/rack_attack.rb",
      %r{start_with\?\("/assets", "/rails/active_storage", "/mcp", "/oauth/token", "/csp-reports"\)}
  end

  test "extends a STATIC_FILE_PREFIXES list" do
    write "config/initializers/rack_attack.rb", "class Rack::Attack\n  STATIC_FILE_PREFIXES = %w[/assets /u/].freeze\nend\n"

    run_generator

    assert_file "config/initializers/rack_attack.rb", %r{STATIC_FILE_PREFIXES = %w\[/assets /u/ /mcp /oauth/token\]}
  end

  test "running twice changes nothing" do
    run_generator %w[--flag beta_mcp]
    files = Dir.glob(File.join(destination_root, "**/*"), File::FNM_DOTMATCH).select { |f| File.file?(f) }
    before = files.to_h { |f| [f, File.read(f)] }

    run_generator %w[--flag beta_mcp]

    after = Dir.glob(File.join(destination_root, "**/*"), File::FNM_DOTMATCH).select { |f| File.file?(f) }
    assert_equal files.sort, after.sort
    files.each { |f| assert_equal before[f], File.read(f), f }
    assert_equal 1, File.read(File.join(destination_root, "config/routes.rb")).scan("generated by maquina:oauth").size
  end

  test "lists what it could not place" do
    File.delete(File.join(destination_root, "config/initializers/rack_attack.rb"))
    File.delete(File.join(destination_root, "config/initializers/filter_parameter_logging.rb"))
    write "test/test_helper.rb", "# custom\n"
    write "app/models/user.rb", "class User < ApplicationRecord\nend\n"

    output = run_generator

    assert_match(/Add to app\/models\/user\.rb.*has_many :access_tokens, dependent: :delete_all\n  has_many :oauth_authorization_codes, dependent: :delete_all/m, output)
    assert_file "app/models/user.rb", "class User < ApplicationRecord\nend\n"
    assert_match(/Rack::Attack \(config\/initializers\/rack_attack\.rb\):.*"\/mcp" and "\/oauth\/token".*oauth\/token\/client/m, output)
    assert_match(/Keep authorization codes out of the logs.*:code_verifier/m, output)
    assert_match(/Load the OAuth test helper in test\/test_helper\.rb/, output)
    assert_no_file "config/initializers/rack_attack.rb"
    assert_file "test/test_helper.rb", "# custom\n"
  end

  test "lists an exemption it cannot place in a custom Rack::Attack file" do
    write "config/initializers/rack_attack.rb", "class Rack::Attack\nend\n"

    output = run_generator

    assert_match(/leave "\/mcp" and "\/oauth\/token" out of the per-IP count/, output)
    assert_file "config/initializers/rack_attack.rb", /oauth\/token\/client/
  end

  test "post-install names the next steps" do
    output = run_generator %w[--prefix /account]

    assert_match(/OAuth for MCP clients has been installed!/, output)
    assert_match(/bin\/rails db:migrate/, output)
    assert_match(/rails g maquina:mcp/, output)
    assert_match(%r{/account/connected_apps}, output)
  end

  test "quiet hides the post-install message" do
    output = run_generator %w[--quiet]

    assert_no_match(/OAuth for MCP clients has been installed/, output)
  end

  private

  def rack_attack_initializer
    options = {login_path: "/session"}
    ERB.new(File.read(RACK_ATTACK_TEMPLATE), trim_mode: "-").result(binding)
  end

  def write(path, content)
    full_path = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  def keys(hash, prefix = nil)
    hash.flat_map { |k, v| v.is_a?(Hash) ? keys(v, "#{prefix}#{k}.") : ["#{prefix}#{k}"] }.sort
  end
end
