require "rails/generators"

module Maquina
  module Generators
    class SolidQueueGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :database, type: :string, default: "sqlite3",
        desc: "Database adapter (sqlite3 uses a separate queue database)"

      # 1. Add gem to Gemfile
      def add_gem
        gemfile_path = File.join(destination_root, "Gemfile")
        if File.exist?(gemfile_path)
          content = File.read(gemfile_path)
          unless content.include?('gem "solid_queue"')
            append_to_file "Gemfile", "\ngem \"solid_queue\"\n"
          end
        end
      end

      # 2. Config file
      def create_config
        template "config/solid_queue.yml", "config/solid_queue.yml"
      end

      # 3. Configure application
      def configure_application
        application_file = File.join(destination_root, "config/application.rb")
        return unless File.exist?(application_file)

        content = File.read(application_file)
        return if content.include?("solid_queue")

        inject_into_file "config/application.rb",
          after: /class Application < Rails::Application\n/ do
          <<~RUBY.indent(4)

            # Use Solid Queue as the Active Job backend in all environments except test
            config.active_job.queue_adapter = :solid_queue unless Rails.env.test?
          RUBY
        end
      end

      # 4. Update Procfile.dev
      def update_procfile
        procfile_path = File.join(destination_root, "Procfile.dev")
        return unless File.exist?(procfile_path)

        content = File.read(procfile_path)
        return if content.include?("solid_queue:")

        append_to_file "Procfile.dev", "solid_queue: bin/rails solid_queue:start\n"
      end

      # 5. Bundle install
      def run_bundle_install
        return unless rails_app?

        Bundler.with_unbundled_env do
          system("bundle install", chdir: destination_root)
        end
      end

      # 6. Install migrations
      def install_migrations
        return unless rails_app?

        Bundler.with_unbundled_env do
          system("bin/rails solid_queue:install:migrations", chdir: destination_root)
        end
      end

      # 7. Post-install message
      def show_post_install
        say ""
        say "Solid Queue has been installed!", :green
        say ""
        say "Next steps:", :yellow
        say "  1. bin/rails db:migrate"
        if options[:database] == "sqlite3"
          say "  2. Configure a separate queue database in config/database.yml:"
          say "     queue:"
          say "       <<: *default"
          say "       database: storage/queue.sqlite3"
          say "       migrations_paths: db/queue_migrate"
        end
        say ""
        say "Configuration:", :yellow
        say "  - Adjust workers/dispatchers in config/solid_queue.yml"
        say "  - Procfile.dev updated with solid_queue process"
        say ""
      end

      private

      def rails_app?
        File.exist?(File.join(destination_root, "bin/rails"))
      end
    end
  end
end
