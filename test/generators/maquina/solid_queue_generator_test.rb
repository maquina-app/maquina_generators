require "test_helper"
require "generators/maquina/solid_queue/solid_queue_generator"
require "generators/maquina/mcp/mcp_generator"

class Maquina::Generators::SolidQueueGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::SolidQueueGenerator
  destination File.expand_path("../../tmp", __dir__)

  setup do
    prepare_destination
    write_host_app
  end

  test "adds gem to Gemfile" do
    run_generator

    assert_file "Gemfile", /gem "solid_queue"/
  end

  test "does not duplicate gem in Gemfile" do
    File.write(
      File.join(destination_root, "Gemfile"),
      "source \"https://rubygems.org\"\ngem \"solid_queue\"\n"
    )

    run_generator

    assert_file "Gemfile" do |content|
      assert_equal 1, content.scan('gem "solid_queue"').length
    end
  end

  test "creates solid_queue config file" do
    run_generator

    assert_file "config/solid_queue.yml" do |content|
      assert_match(/dispatchers:/, content)
      assert_match(/workers:/, content)
      assert_match(/polling_interval:/, content)
      assert_match(/threads: 3/, content)
      assert_match(/recurring:/, content)
      assert_match(/authentication_cleanup:/, content)
      assert_match(/AuthenticationCleanupJob/, content)
      assert_match(/every day at 3am/, content)
    end
  end

  test "configures application to use solid_queue" do
    run_generator

    assert_file "config/application.rb" do |content|
      assert_match(/config\.active_job\.queue_adapter = :solid_queue/, content)
      assert_match(/unless Rails\.env\.test\?/, content)
    end
  end

  test "does not duplicate application config" do
    File.write(
      File.join(destination_root, "config/application.rb"),
      <<~RUBY
        require_relative "boot"
        require "rails/all"

        module TestApp
          class Application < Rails::Application
            config.load_defaults 7.2
            config.active_job.queue_adapter = :solid_queue unless Rails.env.test?
          end
        end
      RUBY
    )

    run_generator

    assert_file "config/application.rb" do |content|
      assert_equal 1, content.scan("solid_queue").length
    end
  end

  test "updates Procfile.dev with solid_queue process" do
    run_generator

    assert_file "Procfile.dev" do |content|
      assert_match(/solid_queue: bin\/rails solid_queue:start/, content)
    end
  end

  test "does not duplicate Procfile.dev entry" do
    File.write(
      File.join(destination_root, "Procfile.dev"),
      "web: bin/rails server -p 3000\nsolid_queue: bin/rails solid_queue:start\n"
    )

    run_generator

    assert_file "Procfile.dev" do |content|
      assert_equal 1, content.scan(/^solid_queue:/).length
    end
  end

  test "skips Procfile.dev update when file does not exist" do
    FileUtils.rm(File.join(destination_root, "Procfile.dev"))

    run_generator

    assert_no_file "Procfile.dev"
  end

  test "writes nothing about MCP without maquina:mcp" do
    output = run_generator %w[--mcp-write]

    assert_no_file "app/models/mcp/tools/solid_queue.rb"
    assert_no_file "test/models/mcp/tools/solid_queue_test.rb"
    assert_no_file "app/agents/error_redactor.rb"
    assert_no_match(/mcp/i, output)
  end

  test "installs the read-only admin MCP tools when maquina:mcp is present" do
    write_mcp_registry

    output = run_generator

    assert_file "app/models/mcp/tools/solid_queue.rb" do |content|
      assert_match(/module Mcp\n  module Tools\n    module SolidQueue/, content)
      assert_match(/ADMIN_ONLY = true/, content)
      assert_match(/WRITE_TOOLS = %w\[\]\.freeze/, content)
      %w[queue_status list_failed_jobs get_failed_job].each do |tool|
        assert_match(/name: "#{tool}"/, content)
        assert_match(/def self\.#{tool}\(scope:/, content)
      end
      assert_match(/::ErrorRedactor\.redact/, content)
      assert_match(/::SolidQueue::FailedExecution/, content)
      assert_no_match(/retry_failed_job/, content)
      assert_no_match(/readOnlyHint: false/, content)
    end
    assert_file "test/models/mcp/tools/solid_queue_test.rb" do |content|
      assert_match(/users\(:mcp_member\)/, content)
      assert_match(/-32602/, content)
    end
    assert_file "app/agents/error_redactor.rb", /class ErrorRedactor/
    assert_no_file "app/agents/failure_triage.rb"
    assert_match(%r{app/models/mcp/tools/solid_queue\.rb}, output)
  end

  test "adds retry_failed_job as a write tool with --mcp-write" do
    write_mcp_registry

    run_generator %w[--mcp-write]

    assert_file "app/models/mcp/tools/solid_queue.rb" do |content|
      assert_match(/WRITE_TOOLS = %w\[retry_failed_job\]\.freeze/, content)
      assert_match(/name: "retry_failed_job"/, content)
      assert_match(/readOnlyHint: false/, content)
      assert_match(/def self\.retry_failed_job\(scope:, id:\)/, content)
    end
  end

  test "both MCP tool variants are valid Ruby" do
    write_mcp_registry

    [[], %w[--mcp-write]].each do |args|
      FileUtils.rm_f(File.join(destination_root, "app/models/mcp/tools/solid_queue.rb"))
      run_generator args

      %w[app/models/mcp/tools/solid_queue.rb test/models/mcp/tools/solid_queue_test.rb].each do |path|
        assert RubyVM::InstructionSequence.compile(File.read(File.join(destination_root, path)))
      end
    end
  end

  test "keeps an existing MCP tool file and says how to add the write tool" do
    write_mcp_registry
    run_generator

    output = run_generator %w[--mcp-write]

    assert_file "app/models/mcp/tools/solid_queue.rb" do |content|
      assert_no_match(/retry_failed_job/, content)
    end
    assert_match(/already exists without retry_failed_job/, output)
  end

  test "running twice with maquina:mcp changes nothing the second time" do
    write_mcp_registry

    run_generator
    first = snapshot
    run_generator

    assert_equal first, snapshot
  end

  test "running before or after maquina:mcp ends in the same files" do
    sibling_first = in_fresh_app do
      run_generator []
      run_mcp_generator
    end
    mcp_first = in_fresh_app do
      run_mcp_generator
      run_generator []
    end

    assert sibling_first.key?("app/models/mcp/tools/solid_queue.rb")
    assert sibling_first.key?("test/models/mcp/tools/solid_queue_test.rb")
    # Both generators add routes at the top of the draw block, so only the
    # order of the routes depends on which ran first.
    assert_equal sibling_first.delete("config/routes.rb").to_s.lines.sort, mcp_first.delete("config/routes.rb").to_s.lines.sort
    assert_equal sibling_first, mcp_first
  end

  test "maquina:mcp installs the read-only tools for an app with only config/queue.yml" do
    in_fresh_app do
      File.write(File.join(destination_root, "config/queue.yml"), "default: {}\n")
      run_mcp_generator
    end

    assert_file "app/models/mcp/tools/solid_queue.rb" do |content|
      assert_match(/WRITE_TOOLS = %w\[\]\.freeze/, content)
      assert_no_match(/def self\.retry_failed_job/, content)
    end
    assert_file "app/agents/error_redactor.rb"
  end

  private

  def write_host_app
    mkdir_p("config")
    File.write(
      File.join(destination_root, "Gemfile"),
      "source \"https://rubygems.org\"\n"
    )

    File.write(
      File.join(destination_root, "config/application.rb"),
      <<~RUBY
        require_relative "boot"
        require "rails/all"

        module TestApp
          class Application < Rails::Application
            config.load_defaults 7.2
          end
        end
      RUBY
    )

    File.write(
      File.join(destination_root, "Procfile.dev"),
      "web: bin/rails server -p 3000\ncss: bin/rails tailwindcss:watch\n"
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
