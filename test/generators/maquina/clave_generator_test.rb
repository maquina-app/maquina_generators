require "test_helper"
require "generators/maquina/clave/clave_generator"

class Maquina::Generators::ClaveGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::ClaveGenerator
  destination File.expand_path("../../tmp", __dir__)

  setup do
    prepare_destination

    # Create a minimal Rails app structure
    mkdir_p("app/controllers")
    File.write(
      File.join(destination_root, "app/controllers/application_controller.rb"),
      "class ApplicationController < ActionController::Base\nend\n"
    )

    mkdir_p("config")
    File.write(
      File.join(destination_root, "config/routes.rb"),
      "Rails.application.routes.draw do\nend\n"
    )

    File.write(
      File.join(destination_root, "Gemfile"),
      "source \"https://rubygems.org\"\n# gem \"bcrypt\"\n"
    )
  end

  test "generates model files" do
    run_generator

    assert_file "app/models/current.rb", /class Current < ActiveSupport::CurrentAttributes/
    assert_file "app/models/session.rb", /class Session < ApplicationRecord/
    assert_file "app/models/email_verification.rb", /class EmailVerification < ApplicationRecord/
    assert_file "app/models/user.rb", /class User < ApplicationRecord/
    assert_file "app/models/user.rb", /has_secure_password/
  end

  test "generates controller files" do
    run_generator

    assert_file "app/controllers/concerns/authentication.rb", /module Authentication/
    assert_file "app/controllers/sessions_controller.rb", /class SessionsController/
    assert_file "app/controllers/session/verifications_controller.rb"
    assert_file "app/controllers/session/verification_resends_controller.rb"
    assert_file "app/controllers/registrations_controller.rb"
    assert_file "app/controllers/registration/verifications_controller.rb"
    assert_file "app/controllers/registration/verification_resends_controller.rb"
  end

  test "generates mailer" do
    run_generator

    assert_file "app/mailers/verification_mailer.rb", /class VerificationMailer/
  end

  test "generates helper" do
    run_generator

    assert_file "app/helpers/authentication_helper.rb", /module AuthenticationHelper/
    assert_file "app/helpers/authentication_helper.rb", /def mask_email/
  end

  test "generates job" do
    run_generator

    assert_file "app/jobs/authentication_cleanup_job.rb", /class AuthenticationCleanupJob/
  end

  test "generates views" do
    run_generator

    assert_file "app/views/sessions/new.html.erb"
    assert_file "app/views/session/verifications/new.html.erb"
    assert_file "app/views/registrations/new.html.erb"
    assert_file "app/views/registration/verifications/new.html.erb"
    assert_file "app/views/verification_mailer/verification_code.html.erb"
    assert_file "app/views/verification_mailer/verification_code.text.erb"
  end

  test "generates locale files" do
    run_generator

    assert_file "config/locales/clave.en.yml", /sessions/
    assert_file "config/locales/clave.es.yml", /sessions/
  end

  test "generates test helper" do
    run_generator

    assert_file "test/test_helpers/session_test_helper.rb", /module SessionTestHelper/
  end

  test "injects authentication into application controller" do
    run_generator

    assert_file "app/controllers/application_controller.rb", /include Authentication/
  end

  test "adds routes" do
    run_generator

    assert_file "config/routes.rb", /resource :session/
    assert_file "config/routes.rb", /resource :registration/
  end

  test "enables bcrypt" do
    run_generator

    assert_file "Gemfile", /^gem "bcrypt"/
  end

  test "generates migrations" do
    run_generator

    assert_migration "db/migrate/create_users.rb"
    assert_migration "db/migrate/create_sessions.rb"
    assert_migration "db/migrate/create_email_verifications.rb"
  end

  test "skips views with --skip-views" do
    run_generator %w[--skip-views]

    assert_no_file "app/views/sessions/new.html.erb"
    assert_no_file "app/views/registrations/new.html.erb"
    # Models should still be generated
    assert_file "app/models/user.rb"
  end

  test "skips registration with --skip-registration" do
    run_generator %w[--skip-registration]

    assert_no_file "app/controllers/registrations_controller.rb"
    assert_no_file "app/controllers/registration/verifications_controller.rb"
    assert_no_file "app/controllers/registration/verification_resends_controller.rb"
    assert_no_file "app/views/registrations/new.html.erb"
    assert_no_file "app/views/registration/verifications/new.html.erb"

    # Session should still be generated
    assert_file "app/controllers/sessions_controller.rb"
    assert_file "app/views/sessions/new.html.erb"

    # Routes should not include registration
    assert_file "config/routes.rb" do |routes|
      assert_match(/resource :session/, routes)
      assert_no_match(/resource :registration/, routes)
    end
  end

  test "authentication concern uses root_url" do
    run_generator

    assert_file "app/controllers/concerns/authentication.rb", /root_url/
    assert_file "app/controllers/concerns/authentication.rb" do |content|
      assert_no_match(/dashboard_url/, content)
    end
  end

  test "user model does not include resto-specific code" do
    run_generator

    assert_file "app/models/user.rb" do |content|
      assert_no_match(/currency/, content)
      assert_no_match(/timezone/, content)
      assert_no_match(/settings/, content)
      assert_no_match(/display_name/, content)
      assert_no_match(/income_sources/, content)
      assert_no_match(/transactions/, content)
    end
  end

  test "views use indigo instead of resto colors" do
    run_generator

    assert_file "app/views/sessions/new.html.erb" do |content|
      assert_match(/indigo/, content)
      assert_no_match(/resto/, content)
    end
  end

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
