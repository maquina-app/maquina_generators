require "test_helper"
require "generators/maquina/solid_queue/solid_queue_generator"

class Maquina::Generators::SolidQueueGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::SolidQueueGenerator
  destination File.expand_path("../../tmp", __dir__)

  setup do
    prepare_destination

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

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
