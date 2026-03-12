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

    assert_file "app/controllers/backstage_controller.rb" do |content|
      assert_match(/class BackstageController < ActionController::Base/, content)
      assert_match(/helper MaquinaComponents::IconsHelper/, content)
      assert_match(/helper MaquinaComponents::EmptyHelper/, content)
      assert_match(/helper MaquinaComponentsHelper/, content)
      assert_match(/helper SolidErrorsHelper/, content)
    end
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

  test "generates helper" do
    run_generator %w[--prefix /admin]

    assert_file "app/helpers/solid_errors_helper.rb" do |content|
      assert_match(/module SolidErrorsHelper/, content)
      assert_match(/severity_badge_variant/, content)
    end
  end

  test "generates initializer with credentials-first auth" do
    run_generator %w[--prefix /admin]

    assert_file "config/initializers/solid_errors.rb" do |content|
      assert_match(/credentials\.backstage/, content)
      assert_match(/ENV\.fetch\("SOLID_ERRORS_USER"/, content)
      assert_match(/ENV\.fetch\("SOLID_ERRORS_PASSWORD"/, content)
      assert_match(/connects_to/, content)
      assert_match(/SolidErrors\.base_controller_class = "BackstageController"/, content)
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

  test "generates admin navigation partial" do
    run_generator %w[--prefix /admin]

    assert_file "app/views/layouts/_admin_navigation.html.erb" do |content|
      assert_match(%r{/admin/solid_errors}, content)
      assert_match(%r{/admin/mission_control_jobs}, content)
      assert_match(/main_app\.root_path/, content)
    end
  end

  test "does not overwrite existing admin navigation" do
    mkdir_p("app/views/layouts")
    File.write(
      File.join(destination_root, "app/views/layouts/_admin_navigation.html.erb"),
      "<nav><!-- custom --></nav>"
    )

    run_generator %w[--prefix /admin]

    assert_file "app/views/layouts/_admin_navigation.html.erb", /<!-- custom -->/
  end

  test "does not copy views with --no-copy-views" do
    run_generator %w[--prefix /admin --no-copy-views]

    assert_no_file "app/views/solid_errors/errors/index.html.erb"
    assert_no_file "app/views/solid_errors/errors/show.html.erb"
  end

  test "copies views by default" do
    run_generator %w[--prefix /admin]

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

  test "copies layout with admin navigation and updated title" do
    run_generator %w[--prefix /admin]

    assert_file "app/views/layouts/solid_errors/application.html.erb" do |content|
      assert_match(/Admin - Errors/, content)
      assert_match(/admin_navigation/, content)
      assert_match(/bg-background/, content)
      assert_match(/javascript_importmap_tags/, content)
    end
  end

  test "copies stimulus controllers" do
    run_generator %w[--prefix /admin]

    assert_file "app/javascript/controllers/clipboard_controller.js" do |content|
      assert_match(/clipboard/, content)
    end
    assert_file "app/javascript/controllers/backtrace_filter_controller.js" do |content|
      assert_match(/filterValueChanged/, content)
    end
  end

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
