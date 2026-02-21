require "test_helper"
require "generators/maquina/solid_errors/solid_errors_generator"

class Maquina::Generators::SolidErrorsGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::SolidErrorsGenerator
  destination File.expand_path("../../tmp", __dir__)

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
  end

  test "generates backstage controller" do
    run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage_controller.rb", /class BackstageController < ActionController::Base/
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

  test "generates initializer with credentials-first auth" do
    run_generator %w[--prefix /admin]

    assert_file "config/initializers/solid_errors.rb" do |content|
      assert_match(/credentials\.backstage/, content)
      assert_match(/ENV\.fetch\("SOLID_ERRORS_USER"/, content)
      assert_match(/ENV\.fetch\("SOLID_ERRORS_PASSWORD"/, content)
      assert_match(/connects_to/, content)
    end
  end

  test "generates initializer with custom env var names" do
    run_generator %w[--prefix /admin --user-env-var ADMIN_USER --password-env-var ADMIN_PASSWORD]

    assert_file "config/initializers/solid_errors.rb" do |content|
      assert_match(/ENV\.fetch\("ADMIN_USER"/, content)
      assert_match(/ENV\.fetch\("ADMIN_PASSWORD"/, content)
    end
  end

  test "adds gem to Gemfile" do
    run_generator %w[--prefix /admin]

    assert_file "Gemfile", /gem "solid_errors"/
  end

  test "does not duplicate gem in Gemfile" do
    File.write(
      File.join(destination_root, "Gemfile"),
      "source \"https://rubygems.org\"\ngem \"solid_errors\"\n"
    )

    run_generator %w[--prefix /admin]

    assert_file "Gemfile" do |content|
      assert_equal 1, content.scan('gem "solid_errors"').length
    end
  end

  test "adds route with prefix" do
    run_generator %w[--prefix /admin]

    assert_file "config/routes.rb", %r{mount SolidErrors::Engine, at: "/admin/solid_errors"}
  end

  test "adds route with custom prefix" do
    run_generator %w[--prefix /backstage]

    assert_file "config/routes.rb", %r{mount SolidErrors::Engine, at: "/backstage/solid_errors"}
  end

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
