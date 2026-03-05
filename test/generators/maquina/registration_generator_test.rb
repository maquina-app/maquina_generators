require "test_helper"
require "generators/maquina/registration/registration_generator"

class Maquina::Generators::RegistrationGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::RegistrationGenerator
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
      "source \"https://rubygems.org\"\n"
    )
  end

  test "generates account model" do
    run_generator

    assert_file "app/models/account.rb", /class Account < ApplicationRecord/
    assert_file "app/models/account.rb", /has_many :users/
    assert_file "app/models/account.rb", /validates :name, presence: true/
  end

  test "generates user model with account association and role" do
    run_generator

    assert_file "app/models/user.rb", /class User < ApplicationRecord/
    assert_file "app/models/user.rb", /has_secure_password/
    assert_file "app/models/user.rb", /belongs_to :account/
    assert_file "app/models/user.rb", /enum :role/
    assert_file "app/models/user.rb", /validates :name, presence: true/
  end

  test "generates current model with account delegation" do
    run_generator

    assert_file "app/models/current.rb", /class Current < ActiveSupport::CurrentAttributes/
    assert_file "app/models/current.rb", /delegate :account, to: :user/
  end

  test "generates registration controller" do
    run_generator

    assert_file "app/controllers/registrations_controller.rb", /class RegistrationsController/
    assert_file "app/controllers/registrations_controller.rb", /allow_unauthenticated_access/
    assert_file "app/controllers/registrations_controller.rb", /rate_limit/
    assert_file "app/controllers/registrations_controller.rb", /Account\.create!/
    assert_file "app/controllers/registrations_controller.rb", /role: :admin/
  end

  test "generates views" do
    run_generator

    assert_file "app/views/registrations/new.html.erb" do |content|
      assert_match(/account_name/, content)
      assert_match(/password_confirmation/, content)
      assert_match(/indigo/, content)
    end

    assert_file "app/views/sessions/new.html.erb" do |content|
      assert_match(/password/, content)
      assert_match(/indigo/, content)
      assert_match(/forgot_password/, content)
    end
  end

  test "generates locale files" do
    run_generator

    assert_file "config/locales/registration.en.yml", /registrations/
    assert_file "config/locales/registration.en.yml", /sessions/
    assert_file "config/locales/registration.es.yml", /registrations/
    assert_file "config/locales/registration.es.yml", /sessions/
  end

  test "adds routes" do
    run_generator

    assert_file "config/routes.rb", /resources :registrations, only: \[:new, :create\]/
  end

  test "generates migrations" do
    run_generator

    assert_migration "db/migrate/create_accounts.rb" do |migration|
      assert_match(/create_table :accounts/, migration)
      assert_match(/t\.string :name/, migration)
    end

    assert_migration "db/migrate/add_account_fields_to_users.rb" do |migration|
      assert_match(/add_reference :users, :account/, migration)
      assert_match(/add_column :users, :role/, migration)
      assert_match(/add_column :users, :name/, migration)
    end
  end

  test "skips views with --skip-views" do
    run_generator %w[--skip-views]

    assert_no_file "app/views/registrations/new.html.erb"
    assert_no_file "app/views/sessions/new.html.erb"
    # Models should still be generated
    assert_file "app/models/account.rb"
    assert_file "app/models/user.rb"
  end

  test "views use indigo color scheme" do
    run_generator

    assert_file "app/views/registrations/new.html.erb" do |content|
      assert_match(/indigo/, content)
    end

    assert_file "app/views/sessions/new.html.erb" do |content|
      assert_match(/indigo/, content)
    end
  end

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
