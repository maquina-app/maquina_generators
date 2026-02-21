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

  test "does not copy views by default" do
    run_generator %w[--prefix /admin]

    assert_no_file "app/views/solid_errors/errors/index.html.erb"
    assert_no_file "app/views/solid_errors/errors/show.html.erb"
  end

  test "copies views with --copy-views" do
    run_generator %w[--prefix /admin --copy-views]

    assert_file "app/views/solid_errors/errors/index.html.erb"
    assert_file "app/views/solid_errors/errors/show.html.erb"
    assert_file "app/views/solid_errors/errors/_error_card.html.erb"
    assert_file "app/views/solid_errors/errors/_delete_button.html.erb"
    assert_file "app/views/solid_errors/errors/_resolve_button.html.erb"
    assert_file "app/views/solid_errors/errors/_actions.html.erb"
    assert_file "app/views/solid_errors/errors/show/_header.html.erb"
    assert_file "app/views/solid_errors/errors/show/_properties.html.erb"
    assert_file "app/views/solid_errors/errors/show/_actions.html.erb"
    assert_file "app/views/solid_errors/errors/show/_error_details.html.erb"
    assert_file "app/views/solid_errors/occurrences/_occurrence.html.erb"
    assert_file "app/views/solid_errors/occurrences/_collection.html.erb"
    assert_file "app/views/solid_errors/occurrences/_backtrace_line.html.erb"
  end

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
