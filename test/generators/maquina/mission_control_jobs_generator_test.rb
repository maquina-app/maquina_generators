require "test_helper"
require "generators/maquina/mission_control_jobs/mission_control_jobs_generator"

class Maquina::Generators::MissionControlJobsGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::MissionControlJobsGenerator
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

  test "generates backstage controller with helpers" do
    run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage_controller.rb" do |content|
      assert_match(/class BackstageController < ActionController::Base/, content)
      assert_match(/helper MaquinaComponents::IconsHelper/, content)
      assert_match(/helper MaquinaComponents::EmptyHelper/, content)
      assert_match(/helper MaquinaComponentsHelper/, content)
      assert_match(/helper MissionControlHelper/, content)
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

    assert_file "app/helpers/mission_control_helper.rb" do |content|
      assert_match(/module MissionControlHelper/, content)
      assert_match(/job_status_badge_variant/, content)
      assert_match(/nav_icon_for_section/, content)
    end
  end

  test "generates initializer with base controller and credentials-first auth" do
    run_generator %w[--prefix /admin]

    assert_file "config/initializers/mission_control.rb" do |content|
      assert_match(/MissionControl::Jobs\.base_controller_class = "BackstageController"/, content)
      assert_match(/MissionControl::Jobs\.adapters = \[:solid_queue\]/, content)
      assert_match(/credentials\.backstage/, content)
      assert_match(/ENV\.fetch\("MISSION_CONTROL_JOBS_USER"/, content)
      assert_match(/ENV\.fetch\("MISSION_CONTROL_JOBS_PASSWORD"/, content)
    end
  end

  test "generates initializer with custom env var names" do
    run_generator %w[--prefix /admin --user-env-var ADMIN_USER --password-env-var ADMIN_PASSWORD]

    assert_file "config/initializers/mission_control.rb" do |content|
      assert_match(/ENV\.fetch\("ADMIN_USER"/, content)
      assert_match(/ENV\.fetch\("ADMIN_PASSWORD"/, content)
    end
  end

  test "adds gem to Gemfile" do
    run_generator %w[--prefix /admin]

    assert_file "Gemfile", /gem "mission_control-jobs"/
  end

  test "does not duplicate gem in Gemfile" do
    File.write(
      File.join(destination_root, "Gemfile"),
      "source \"https://rubygems.org\"\ngem \"mission_control-jobs\"\n"
    )

    run_generator %w[--prefix /admin]

    assert_file "Gemfile" do |content|
      assert_equal 1, content.scan('gem "mission_control-jobs"').length
    end
  end

  test "adds route with prefix" do
    run_generator %w[--prefix /admin]

    assert_file "config/routes.rb", %r{mount MissionControl::Jobs::Engine, at: "/admin/mission_control_jobs"}
  end

  test "adds route with custom prefix" do
    run_generator %w[--prefix /backstage]

    assert_file "config/routes.rb", %r{mount MissionControl::Jobs::Engine, at: "/backstage/mission_control_jobs"}
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

  test "copies layout by default" do
    run_generator %w[--prefix /admin]

    assert_file "app/views/layouts/mission_control/jobs/application.html.erb" do |content|
      assert_match(/Admin - Jobs/, content)
      assert_match(/admin_navigation/, content)
    end
    assert_file "app/views/layouts/mission_control/jobs/_navigation.html.erb"
    assert_file "app/views/layouts/mission_control/jobs/_application_selection.html.erb"
    assert_file "app/views/layouts/mission_control/jobs/application_selection/_servers.html.erb"
    assert_file "app/views/layouts/mission_control/jobs/application_selection/_applications.html.erb"
  end

  test "copies views by default" do
    run_generator %w[--prefix /admin]

    assert_file "app/views/mission_control/jobs/jobs/index.html.erb"
    assert_file "app/views/mission_control/jobs/jobs/show.html.erb"
    assert_file "app/views/mission_control/jobs/queues/index.html.erb"
    assert_file "app/views/mission_control/jobs/queues/show.html.erb"
    assert_file "app/views/mission_control/jobs/workers/index.html.erb"
    assert_file "app/views/mission_control/jobs/workers/show.html.erb"
    assert_file "app/views/mission_control/jobs/recurring_tasks/index.html.erb"
    assert_file "app/views/mission_control/jobs/recurring_tasks/show.html.erb"
    assert_file "app/views/mission_control/jobs/shared/_pagination_toolbar.html.erb"
  end

  test "does not copy views with --no-copy-views" do
    run_generator %w[--prefix /admin --no-copy-views]

    assert_no_file "app/views/mission_control/jobs/jobs/index.html.erb"
    assert_no_file "app/views/mission_control/jobs/queues/index.html.erb"
    assert_no_file "app/views/mission_control/jobs/workers/index.html.erb"
    assert_no_file "app/views/mission_control/jobs/recurring_tasks/index.html.erb"
  end

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
