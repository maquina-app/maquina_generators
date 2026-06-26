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

  test "copies self-contained mailer templates that avoid dashboard-only helpers" do
    run_generator %w[--prefix /admin]

    %w[
      app/views/solid_errors/error_mailer/error_occurred.html.erb
      app/views/solid_errors/error_mailer/error_occurred.text.erb
    ].each do |path|
      assert_file path do |content|
        # The mailer renders without the BackstageController helpers, so these
        # templates must not reuse the themed dashboard partials or their
        # icon_for/Stimulus dependencies (the cause of the email render loop).
        body = content.gsub(/<%#.*?%>/m, "")
        assert_no_match(/icon_for/, body)
        assert_no_match(/data-controller/, body)
        assert_no_match(%r{render\s+["']solid_errors/}, body)
      end
    end
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

  test "injects job context hook into ApplicationJob" do
    write_application_job

    run_generator %w[--prefix /admin]

    assert_file "app/jobs/application_job.rb" do |content|
      assert_match(/around_perform do \|job, block\|/, content)
      assert_match(/Rails\.error\.set_context/, content)
      assert_match(/active_job: job\.class\.name/, content)
      assert_match(/arguments: job\.arguments/, content)
      assert_match(/job_id: job\.job_id/, content)
    end
  end

  test "injects job context hook even without --agent" do
    write_application_job

    run_generator %w[--prefix /admin]

    assert_file "app/jobs/application_job.rb", /Rails\.error\.set_context/
  end

  test "does not duplicate job context hook" do
    write_application_job

    run_generator %w[--prefix /admin]
    run_generator %w[--prefix /admin]

    assert_file "app/jobs/application_job.rb" do |content|
      assert_equal 1, content.scan("Rails.error.set_context").length
    end
  end

  test "skips job hook when ApplicationJob is absent" do
    run_generator %w[--prefix /admin]

    assert_no_file "app/jobs/application_job.rb"
  end

  test "does not generate agent tooling by default" do
    run_generator %w[--prefix /admin]

    assert_no_file "app/agents/errors_query.rb"
    assert_no_file "bin/failures"
    assert_no_file "bin/failures-mcp"
    assert_file "Gemfile" do |content|
      assert_no_match(/gem "mcp"/, content)
    end
  end

  test "generates agent tooling with --agent" do
    run_generator %w[--prefix /admin --agent]

    assert_file "app/agents/error_redactor.rb", /class ErrorRedactor/
    assert_file "app/agents/errors_query.rb", /class ErrorsQuery/
    assert_file "app/agents/failure_triage.rb", /class FailureTriage/
    assert_file "app/agents/list_failures_tool.rb" do |content|
      assert_match(/class ListFailuresTool < MCP::Tool/, content)
      assert_match(/tool_name "list_failures"/, content)
    end
    assert_file "app/agents/get_exception_tool.rb", /tool_name "get_exception"/
    assert_file "app/agents/top_exceptions_tool.rb", /tool_name "top_exceptions"/
  end

  test "generates executable bin runners with --agent" do
    run_generator %w[--prefix /admin --agent]

    assert_file "bin/failures", %r{FailureTriage\.overview}
    assert_file "bin/failures-mcp" do |content|
      assert_match(/MCP::Server\.new/, content)
      assert_match(/StdioTransport/, content)
    end
    assert File.executable?(File.join(destination_root, "bin/failures"))
    assert File.executable?(File.join(destination_root, "bin/failures-mcp"))
  end

  test "adds mcp gem with --agent" do
    run_generator %w[--prefix /admin --agent]

    assert_file "Gemfile", /gem "mcp"/
  end

  test "redaction layer masks sensitive keys" do
    run_generator %w[--prefix /admin --agent]

    assert_file "app/agents/error_redactor.rb" do |content|
      assert_match(/SENSITIVE_KEY_PATTERN/, content)
      assert_match(/pass\(word\)\?|token|secret/, content)
    end
  end

  test "does not generate MCP-over-HTTP controller without --mcp-http" do
    run_generator %w[--prefix /admin --agent]

    assert_no_file "app/controllers/failures_mcp_controller.rb"
    assert_file "config/routes.rb" do |content|
      assert_no_match(/failures_mcp#handle/, content)
    end
  end

  test "generates MCP-over-HTTP controller and route with --mcp-http" do
    run_generator %w[--prefix /admin --mcp-http]

    assert_file "app/controllers/failures_mcp_controller.rb" do |content|
      assert_match(/class FailuresMcpController < ActionController::Base/, content)
      assert_match(/skip_forgery_protection/, content)
      assert_match(/StreamableHTTPTransport/, content)
      assert_match(/credentials\.backstage/, content)
      assert_match(/secure_compare/, content)
      assert_match(/head :service_unavailable/, content)
    end
    assert_file "config/routes.rb",
      %r{match "/admin/failures/mcp", to: "failures_mcp#handle", via: %i\[get post delete\]}
  end

  test "mcp-http controller uses configured auth env vars" do
    run_generator %w[--prefix /admin --mcp-http --user-env-var ADMIN_USER --password-env-var ADMIN_PASSWORD]

    assert_file "app/controllers/failures_mcp_controller.rb" do |content|
      assert_match(/ENV\["ADMIN_USER"\]/, content)
      assert_match(/ENV\["ADMIN_PASSWORD"\]/, content)
    end
  end

  test "--mcp-http implies --agent" do
    run_generator %w[--prefix /admin --mcp-http]

    assert_file "app/agents/failure_triage.rb"
    assert_file "bin/failures-mcp"
    assert_file "Gemfile", /gem "mcp"/
  end

  private

  def write_application_job
    mkdir_p("app/jobs")
    File.write(
      File.join(destination_root, "app/jobs/application_job.rb"),
      "class ApplicationJob < ActiveJob::Base\nend\n"
    )
  end

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
