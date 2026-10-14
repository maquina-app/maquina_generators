require "test_helper"
require "generators/maquina/passkeys/passkeys_generator"

class Maquina::Generators::PasskeysGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::PasskeysGenerator
  destination File.expand_path("../../tmp", __dir__)

  CLAVE_TEMPLATES = File.expand_path("../../../lib/generators/maquina/clave/templates", __dir__)

  setup do
    prepare_destination
    write "config/routes.rb", "Rails.application.routes.draw do\nend\n"
    write "Gemfile", "source \"https://rubygems.org\"\n"
    write "app/models/email_verification.rb", "class EmailVerification < ApplicationRecord\nend\n"
    write "app/controllers/concerns/authentication.rb", "module Authentication\nend\n"
    # The files clave generates, as clave generates them.
    write "app/models/user.rb", File.read(File.join(CLAVE_TEMPLATES, "app/models/user.rb.tt"))
    write "app/views/sessions/new.html.erb", clave_sign_in_page
    write "config/initializers/rack_attack.rb", "class Rack::Attack\nend\n"
    write "test/test_helper.rb", TEST_HELPER
  end

  TEST_HELPER = <<~RUBY
    ENV["RAILS_ENV"] ||= "test"
    require_relative "../config/environment"
    require "rails/test_help"
  RUBY

  test "refuses to run without clave" do
    File.delete(File.join(destination_root, "app/models/email_verification.rb"))

    output = capture(:stderr) { run_generator }

    assert_match(/Run `rails g maquina:clave` first/, output)
    assert_no_file "app/models/passkey.rb"
  end

  test "adds the webauthn gem" do
    run_generator

    assert_file "Gemfile", /^gem "webauthn", "~> 3\.4"$/
  end

  test "creates the relying party initializer" do
    run_generator

    assert_file "config/initializers/webauthn.rb" do |content|
      assert_match(/config\.rp_id = ENV\["WEBAUTHN_RP_ID"\]/, content)
      assert_match(/config\.allowed_origins = /, content)
      assert_match(/raise "Passkeys: set WEBAUTHN_RP_ID/, content)
    end
  end

  test "creates the passkey model and wires it into the user" do
    run_generator

    assert_file "app/models/passkey.rb", /class Passkey < ApplicationRecord/
    assert_file "app/models/user.rb" do |content|
      assert_match(/has_many :sessions, dependent: :destroy\n  has_many :passkeys, dependent: :destroy\n/, content)
      assert_match(/def webauthn_id\n    super \|\| begin\n      update_column\(:webauthn_id, WebAuthn\.generate_user_id\)/, content)
      assert_operator content.index("def webauthn_id"), :<, content.index("  private")
    end
  end

  test "creates the migrations" do
    run_generator

    assert_migration "db/migrate/add_webauthn_id_to_users.rb", /add_index :users, :webauthn_id, unique: true/
    assert_migration "db/migrate/create_passkeys.rb" do |content|
      assert_match(/t\.string :credential_id, null: false/, content)
      assert_match(/t\.text :public_key, null: false/, content)
      assert_match(/t\.bigint :sign_count, null: false, default: 0/, content)
      assert_match(/add_index :passkeys, :credential_id, unique: true/, content)
    end
  end

  test "creates the controllers and routes" do
    run_generator

    assert_file "app/controllers/session/passkey_challenges_controller.rb", /class Session::PasskeyChallengesController/
    assert_file "app/controllers/session/passkeys_controller.rb", /class Session::PasskeysController/
    assert_file "app/controllers/passkey_challenges_controller.rb", /class PasskeyChallengesController/
    assert_file "app/controllers/passkeys_controller.rb", /class PasskeysController/
    assert_file "app/controllers/concerns/passkey_challenge.rb", /module PasskeyChallenge/
    assert_file "app/controllers/concerns/passkey_reauthentication.rb", /module PasskeyReauthentication/
    assert_file "config/routes.rb" do |content|
      assert_match(/resource :passkey_challenge, only: :create, controller: "session\/passkey_challenges"/, content)
      assert_match(/resource :passkey, only: :create, controller: "session\/passkeys"/, content)
      assert_match(/resources :passkeys, only: \[:index, :create, :update, :destroy\]/, content)
    end
  end

  test "sign-in offers every passkey and requires user verification" do
    run_generator

    assert_file "app/controllers/session/passkey_challenges_controller.rb" do |content|
      assert_match(/options_for_get\(user_verification: "required"\)/, content)
      assert_no_match(/allow:/, content)
    end
    assert_file "app/controllers/session/passkeys_controller.rb" do |content|
      assert_match(/allow_unauthenticated_access/, content)
      assert_match(/rate_limit to:/, content)
      assert_match(/sign_count: passkey\.sign_count, user_verification: true\)/, content)
      assert_match(/credential\.user_handle != user\.webauthn_id/, content)
      assert_match(/start_new_session_for\(user\)/, content)
      # The challenge is gone from the session before anything is verified.
      assert_operator content.index("take_passkey_challenge"), :<, content.index("credential.verify")
    end
    assert_file "app/controllers/concerns/passkey_challenge.rb", /stored = session\.delete\(passkey_challenge_key\(purpose\)\)/
  end

  test "registration makes discoverable passkeys behind a recent sign-in" do
    run_generator

    assert_file "app/controllers/passkey_challenges_controller.rb" do |content|
      assert_match(/include PasskeyReauthentication/, content)
      assert_match(/resident_key: "required", user_verification: "required"/, content)
      assert_match(/exclude: user\.passkeys\.pluck\(:credential_id\)/, content)
    end
    assert_file "app/controllers/passkeys_controller.rb" do |content|
      assert_match(/include PasskeyReauthentication/, content)
      assert_match(/credential\.verify\(challenge, user_verification: true\)/, content)
      assert_match(/Current\.user\.passkeys\.find\(params\[:id\]\)/, content)
    end
  end

  test "renaming and removing redirect with 303 and the remove button stays readable" do
    run_generator

    assert_file "app/controllers/passkeys_controller.rb" do |content|
      assert_equal 3, content.scan(/redirect_to passkeys_path, .*status: :see_other$/).size
      assert_no_match(/redirect_to(?!.*see_other)/, content)
    end
    assert_file "app/views/passkeys/index.html.erb" do |content|
      assert_no_match(/variant: "destructive"/, content)
      assert_match(/variant: "ghost" },\n\s+class: "[^"]*text-destructive hover:bg-destructive\/10/, content)
    end
  end

  test "adds the passkey button and autofill to the sign-in page" do
    run_generator

    # Visible as rendered, refreshed after a Turbo morph (which doesn't reconnect).
    assert_file "app/views/sessions/_passkey.html.erb" do |content|
      assert_match(/data-action="turbo:morph@document->passkey-sign-in#refresh"/, content)
      assert_match(/class="mt-6 space-y-4">/, content)
    end
    assert_file "app/views/passkeys/index.html.erb" do |content|
      assert_match(/data-action="turbo:morph@document->passkey-registration#refresh"/, content)
      assert_no_match(/disabled:opacity-50"\s+hidden>/, content)
    end
    assert_file "app/javascript/controllers/passkey_sign_in_controller.js", /mediation: "conditional"|\{ mediation \}/
    assert_file "app/javascript/controllers/passkey_registration_controller.js", /parseCreationOptionsFromJSON/
    assert_file "app/views/sessions/new.html.erb" do |content|
      assert_match(/autocomplete: "username webauthn"/, content)
      assert_match(/<% end %>\n\n      <%= render "sessions\/passkey" %>\n/, content)
    end
  end

  test "the JavaScript needs no WebAuthn library" do
    run_generator

    %w[passkey_sign_in_controller.js passkey_registration_controller.js].each do |file|
      assert_file "app/javascript/controllers/#{file}" do |content|
        assert_equal ['import { Controller } from "@hotwired/stimulus"'], content.scan(/^import .*$/)
      end
    end
  end

  test "adds the passkey button to a sign-in page without sign-up" do
    write "app/views/sessions/new.html.erb", clave_sign_in_page(skip_registration: true)

    run_generator

    assert_file "app/views/sessions/new.html.erb" do |content|
      assert_match(/<% end %>\n\n      <%= render "sessions\/passkey" %>\n    <\/div>/, content)
      assert_match(/autocomplete: "username webauthn"/, content)
    end
  end

  test "skip-views leaves the pages and the sign-in form alone" do
    run_generator ["--skip-views"]

    assert_no_file "app/views/passkeys/index.html.erb"
    assert_no_file "app/javascript/controllers/passkey_sign_in_controller.js"
    assert_file "app/views/sessions/new.html.erb" do |content|
      assert_no_match(/passkey/, content)
    end
  end

  test "creates locales and the test helper" do
    run_generator

    assert_file "config/locales/passkeys.en.yml", /sign_in: "Sign in with a passkey"/
    assert_file "config/locales/passkeys.es.yml", /sign_in: "Iniciar sesión con llave de acceso"/
    assert_file "test/test_helpers/webauthn_test_helper.rb", /require "webauthn\/fake_client"/
    assert_file "test/integration/passkeys_test.rb", /sign_in_with_passkey\(@user\)/
    assert_file "test/test_helper.rb", /require "rails\/test_help"\nrequire_relative "test_helpers\/webauthn_test_helper"\n/
  end

  test "locales share the same keys" do
    run_generator

    en = YAML.load_file(File.join(destination_root, "config/locales/passkeys.en.yml"))["en"]
    es = YAML.load_file(File.join(destination_root, "config/locales/passkeys.es.yml"))["es"]
    assert_equal keys(en), keys(es)
  end

  test "throttles passkey sign-in in rack attack" do
    run_generator

    assert_file "config/initializers/rack_attack.rb", /Rack::Attack\.throttle\("passkey\/ip", limit: 20, period: 1\.minute\)/
    assert_file "config/initializers/rack_attack.rb", /\(req\.env\["action_dispatch\.remote_ip"\]&\.to_s \|\| req\.ip\) if req\.path\.start_with\?\("\/session\/passkey"\)/
  end

  test "running twice changes nothing" do
    run_generator
    files = %w[Gemfile config/routes.rb app/models/user.rb app/views/sessions/new.html.erb config/initializers/rack_attack.rb
      test/test_helper.rb]
    before = files.to_h { |f| [f, File.read(File.join(destination_root, f))] }

    run_generator

    files.each { |f| assert_equal before[f], File.read(File.join(destination_root, f)), f }
  end

  test "lists what it could not place" do
    write "app/models/user.rb", "class User < ApplicationRecord\nend\n"
    write "app/views/sessions/new.html.erb", "<h1>Sign in</h1>\n"
    File.delete(File.join(destination_root, "config/initializers/rack_attack.rb"))
    write "test/test_helper.rb", "# custom\n"

    output = run_generator

    assert_match(/Add to app\/models\/user\.rb:.*has_many :passkeys/m, output)
    assert_match(/Offer passkeys on the sign-in page/, output)
    assert_match(/Throttle passkey sign-in in config\/initializers\/rack_attack\.rb/, output)
    assert_match(/Load the passkey test helper in test\/test_helper\.rb/, output)
    assert_file "app/models/user.rb", "class User < ApplicationRecord\nend\n"
    assert_file "app/views/sessions/new.html.erb", "<h1>Sign in</h1>\n"
  end

  test "quiet hides the post-install message" do
    output = run_generator ["--quiet"]

    assert_no_match(/Passkeys have been installed/, output)
  end

  private

  # Clave's sign-in page as `rails g maquina:clave` renders it.
  def clave_sign_in_page(skip_registration: false)
    template = File.read(File.join(CLAVE_TEMPLATES, "app/views/sessions/new.html.erb.tt"))
    options = {skip_registration: skip_registration}
    ERB.new(template, trim_mode: "-").result(binding)
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
