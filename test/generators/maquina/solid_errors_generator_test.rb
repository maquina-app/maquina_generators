require "test_helper"
require "generators/maquina/solid_errors/solid_errors_generator"
require "generators/maquina/mcp/mcp_generator"

class Maquina::Generators::SolidErrorsGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::SolidErrorsGenerator
  destination File.expand_path("../../tmp", __dir__)

  setup do
    prepare_destination
    write_host_app
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

    assert_file "config/routes.rb", %r{mount SolidErrors::Engine, at: "/admin/errors"}
  end

  test "adds route with custom prefix" do
    run_generator %w[--prefix /backstage]

    assert_file "config/routes.rb", %r{mount SolidErrors::Engine, at: "/backstage/errors"}
  end

  test "generates admin navigation partial" do
    run_generator %w[--prefix /admin]

    assert_file "app/views/layouts/_admin_navigation.html.erb" do |content|
      assert_match(%r{/admin/errors}, content)
      assert_match(%r{/admin/jobs}, content)
      assert_match(/main_app\.root_path/, content)
    end
  end

  test "navigation includes an Overview tab pointing at the prefix root" do
    run_generator %w[--prefix /admin]

    assert_file "app/views/layouts/_admin_navigation.html.erb" do |content|
      assert_match(/<span>Overview<\/span>/, content)
      assert_match(%r{link_to "/admin",}, content)
    end
  end

  test "installs the backstage dashboard" do
    run_generator %w[--prefix /admin]

    assert_file "app/controllers/backstage_dashboard_controller.rb" do |content|
      assert_match(/class BackstageDashboardController < BackstageController/, content)
      assert_match(/authenticate_or_request_with_http_basic/, content)
      assert_match(/@metrics = \[\]/, content)
    end
    assert_file "app/views/layouts/admin.html.erb", /admin_navigation/
    assert_file "app/views/backstage_dashboard/index.html.erb" do |content|
      assert_match(/Overview/, content)
      assert_match(%r{defined\?\(SolidErrors::Engine\)}, content)
      assert_match(%r{"/admin/errors"}, content)
      assert_match(%r{"/admin/jobs"}, content)
    end
    assert_file "config/routes.rb", %r{get "/admin" => "backstage_dashboard#index"}
  end

  test "does not duplicate the dashboard route when run twice" do
    run_generator %w[--prefix /admin]
    run_generator %w[--prefix /admin]

    assert_file "config/routes.rb" do |content|
      assert_equal 1, content.scan("backstage_dashboard#index").length
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

  test "has no --mcp-http option or HTTP MCP controller" do
    refute Maquina::Generators::SolidErrorsGenerator.class_options.key?(:mcp_http)

    run_generator %w[--prefix /admin --agent]

    assert_no_file "app/controllers/failures_mcp_controller.rb"
    assert_file "config/routes.rb" do |content|
      assert_no_match(/failures_mcp/, content)
    end
  end

  test "writes nothing about MCP without maquina:mcp" do
    output = run_generator %w[--prefix /admin]

    assert_no_file "app/models/mcp/tools/solid_errors.rb"
    assert_no_file "test/models/mcp/tools/solid_errors_test.rb"
    assert_no_file "app/agents/failure_triage.rb"
    assert_no_match(/mcp/i, output)
  end

  test "installs the admin-only MCP tools and the query layer they call when maquina:mcp is present" do
    write_mcp_registry

    output = run_generator %w[--prefix /admin]

    assert_file "app/models/mcp/tools/solid_errors.rb" do |content|
      assert_match(/module Mcp\n  module Tools\n    module SolidErrors/, content)
      assert_match(/ADMIN_ONLY = true/, content)
      assert_match(/WRITE_TOOLS = %w\[\]\.freeze/, content)
      %w[list_failures get_failure top_exceptions].each do |tool|
        assert_match(/name: "#{tool}"/, content)
        assert_match(/def self\.#{tool}\(scope:/, content)
      end
      assert_match(/::FailureTriage\.overview/, content)
      assert_match(/clamp\(1, MAX_LIMIT\)/, content)
      assert_no_match(/readOnlyHint: false/, content)
    end
    assert_file "test/models/mcp/tools/solid_errors_test.rb" do |content|
      assert_match(/users\(:mcp_member\)/, content)
      assert_match(/-32602/, content)
      assert_match(/tools\/list/, content)
    end
    assert_file "app/agents/error_redactor.rb", /class ErrorRedactor/
    assert_file "app/agents/errors_query.rb", /class ErrorsQuery/
    assert_file "app/agents/failure_triage.rb", /class FailureTriage/
    assert_no_file "app/agents/list_failures_tool.rb"
    assert_no_file "bin/failures"
    assert_file "Gemfile" do |content|
      assert_no_match(/gem "mcp"/, content)
    end
    assert_match(%r{app/models/mcp/tools/solid_errors\.rb}, output)
  end

  test "generated MCP files are valid Ruby" do
    write_mcp_registry

    run_generator %w[--prefix /admin]

    %w[app/models/mcp/tools/solid_errors.rb test/models/mcp/tools/solid_errors_test.rb].each do |path|
      assert RubyVM::InstructionSequence.compile(File.read(File.join(destination_root, path)))
    end
  end

  test "installs the MCP tools alongside --agent" do
    write_mcp_registry

    run_generator %w[--prefix /admin --agent]

    assert_file "app/models/mcp/tools/solid_errors.rb"
    assert_file "app/agents/list_failures_tool.rb"
    assert_file "bin/failures-mcp"
  end

  test "keeps an existing MCP tool file and agent files" do
    write_mcp_registry
    mkdir_p("app/models/mcp/tools")
    mkdir_p("app/agents")
    File.write(File.join(destination_root, "app/models/mcp/tools/solid_errors.rb"), "# custom tools\n")
    File.write(File.join(destination_root, "app/agents/error_redactor.rb"), "# custom redactor\n")

    run_generator %w[--prefix /admin]

    assert_file "app/models/mcp/tools/solid_errors.rb", "# custom tools\n"
    assert_file "app/agents/error_redactor.rb", "# custom redactor\n"
    assert_file "app/agents/failure_triage.rb", /class FailureTriage/
  end

  test "running twice with maquina:mcp changes nothing the second time" do
    write_mcp_registry

    run_generator %w[--prefix /admin]
    first = snapshot
    run_generator %w[--prefix /admin]

    assert_equal first, snapshot
  end

  test "running before or after maquina:mcp ends in the same files" do
    sibling_first = in_fresh_app do
      run_generator %w[--prefix /admin]
      run_mcp_generator
    end
    mcp_first = in_fresh_app do
      run_mcp_generator
      run_generator %w[--prefix /admin]
    end

    assert sibling_first.key?("app/models/mcp/tools/solid_errors.rb")
    assert sibling_first.key?("test/models/mcp/tools/solid_errors_test.rb")
    # Both generators add routes at the top of the draw block, so only the
    # order of the routes depends on which ran first.
    assert_equal sibling_first.delete("config/routes.rb").to_s.lines.sort, mcp_first.delete("config/routes.rb").to_s.lines.sort
    assert_equal sibling_first, mcp_first
  end

  private

  def write_host_app
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

  def write_application_job
    mkdir_p("app/jobs")
    File.write(
      File.join(destination_root, "app/jobs/application_job.rb"),
      "class ApplicationJob < ActiveJob::Base\nend\n"
    )
  end

  # app/models/mcp/tools.rb is what tells a sibling generator maquina:mcp ran.
  def write_mcp_registry
    mkdir_p("app/models/mcp")
    File.write(File.join(destination_root, "app/models/mcp/tools.rb"), "module Mcp\n  module Tools\n  end\nend\n")
  end

  # The files an app ends with after the block, from a fresh copy of the host
  # app that maquina:oauth has run on. Migration timestamps are normalized.
  def in_fresh_app
    prepare_destination
    write_host_app
    FileUtils.mkdir_p(File.join(destination_root, "app/models"))
    File.write(File.join(destination_root, "app/models/access_token.rb"), "class AccessToken < ApplicationRecord\nend\n")
    yield
    snapshot.to_h do |path, content|
      [path.gsub(/\d{14}/, "TIMESTAMP"), content.gsub(/\d{4}_\d{2}_\d{2}_\d{6}/, "VERSION")]
    end
  end

  def run_mcp_generator
    capture(:stdout) { Maquina::Generators::McpGenerator.start(["--quiet"], destination_root: destination_root) }
  end

  def snapshot
    Dir.glob("**/*", base: destination_root).sort
      .reject { |path| File.directory?(File.join(destination_root, path)) }
      .to_h { |path| [path, File.read(File.join(destination_root, path))] }
  end

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
