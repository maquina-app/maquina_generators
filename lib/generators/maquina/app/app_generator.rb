require "rails/generators"

module Maquina
  module Generators
    class AppGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :prefix, type: :string, default: "/admin",
        desc: "Base path prefix for backstage tools"
      class_option :port, type: :string, default: "3000",
        desc: "Default port for development server"
      class_option :auth, type: :string, default: "none",
        desc: "Authentication type: none, clave, or registration"

      # 1. Add gems
      def add_gems
        gemfile_path = File.join(destination_root, "Gemfile")
        return unless File.exist?(gemfile_path)

        content = File.read(gemfile_path)

        dev_gems = {"brakeman" => nil, "bundle-audit" => nil, "letter_opener" => nil, "standard" => nil}
        runtime_gems = {"rails-i18n" => nil, "maquina_components" => nil}
        production_gems = {"aws-sdk-s3" => nil}

        dev_gems.each do |gem_name, _|
          unless content.include?("gem \"#{gem_name}\"")
            append_to_file "Gemfile", "\ngem \"#{gem_name}\", group: :development\n"
          end
        end

        runtime_gems.each do |gem_name, _|
          unless content.include?("gem \"#{gem_name}\"")
            append_to_file "Gemfile", "\ngem \"#{gem_name}\"\n"
          end
        end

        production_gems.each do |gem_name, _|
          unless content.include?("gem \"#{gem_name}\"")
            append_to_file "Gemfile", "\ngem \"#{gem_name}\", group: :production\n"
          end
        end

        return unless rails_app?

        Bundler.with_unbundled_env do
          system("bundle install", chdir: destination_root)
        end
      end

      # 2. Create Procfile.dev
      def create_procfile
        template "Procfile.dev.tt", "Procfile.dev"
      end

      # 3. Config files
      def create_config_files
        copy_file ".rubocop.yml", ".rubocop.yml"
        copy_file ".standard.yml", ".standard.yml"

        gitignore_path = File.join(destination_root, ".gitignore")
        if File.exist?(gitignore_path)
          content = File.read(gitignore_path)
          unless content.include?("config/database.yml")
            append_to_file ".gitignore", "\n# Ignore database configuration\nconfig/database.yml\n"
          end
        end
      end

      # 4. Scripts
      def create_scripts
        template "bin/setup.tt", "bin/setup"
        copy_file "bin/ci", "bin/ci"
        chmod "bin/setup", 0o755
        chmod "bin/ci", 0o755
      end

      # 5. Initializers
      def create_initializers
        copy_file "config/initializers/generators.rb",
          "config/initializers/generators.rb"
      end

      # 6. Configure environments
      def configure_environments
        configure_development
        configure_production
      end

      # 7. Configure application
      def configure_application
        application_file = File.join(destination_root, "config/application.rb")
        return unless File.exist?(application_file)

        content = File.read(application_file)

        unless content.include?("field_error_proc")
          inject_into_file "config/application.rb",
            after: /class Application < Rails::Application\n/ do
            <<~RUBY.indent(4)

              # Don't wrap form fields with errors in an extra div
              config.action_view.field_error_proc = proc { |html_tag, _instance| html_tag }
            RUBY
          end
        end
      end

      # 8. Install Rails features
      def install_rails_features
        return unless rails_app?

        Bundler.with_unbundled_env do
          system("bin/rails action_text:install", chdir: destination_root)
          system("bin/rails active_storage:install", chdir: destination_root)
          system("bin/rails db:migrate", chdir: destination_root)
        end
      end

      # 9. Setup JavaScript
      def setup_javascript
        return unless rails_app?

        importmap_path = File.join(destination_root, "config/importmap.rb")
        if File.exist?(importmap_path)
          content = File.read(importmap_path)
          unless content.include?("activestorage")
            append_to_file "config/importmap.rb",
              "\npin \"@rails/activestorage\", to: \"activestorage.esm.js\"\n"
          end
        end

        js_path = File.join(destination_root, "app/javascript/application.js")
        if File.exist?(js_path)
          content = File.read(js_path)
          unless content.include?("ActiveStorage")
            append_to_file "app/javascript/application.js", <<~JS

              import * as ActiveStorage from "@rails/activestorage"
              ActiveStorage.start()
            JS
          end
        end
      end

      # 10. Setup layout
      def setup_layout
        layout_path = File.join(destination_root, "app/views/layouts/application.html.erb")
        return unless File.exist?(layout_path)

        content = File.read(layout_path)

        unless content.include?("yield :head")
          gsub_file "app/views/layouts/application.html.erb",
            "</head>",
            "    <%= yield :head %>\n  </head>"
        end

        unless content.include?("data-turbo-refresh-method")
          gsub_file "app/views/layouts/application.html.erb",
            "<body>",
            '<body data-turbo-refresh-method="morph" data-turbo-refresh-scroll="preserve">'
        end
      end

      # 11. Install authentication
      def install_authentication
        return unless rails_app?

        case options[:auth]
        when "clave"
          generate "maquina:clave"
        when "registration"
          generate "maquina:registration"
        end
      end

      # 12. Install maquina generators
      def install_maquina_generators
        return unless rails_app?

        generate "maquina:rack_attack"
        generate "maquina:solid_queue"
        generate "maquina:mission_control_jobs", "--prefix", options[:prefix]
        generate "maquina:solid_errors", "--prefix", options[:prefix]

        Bundler.with_unbundled_env do
          system("bin/rails maquina_components:install", chdir: destination_root)
        end
      end

      # 13. Create home page
      def create_home_page
        template "app/controllers/home_controller.rb",
          "app/controllers/home_controller.rb"
        template "app/views/home/index.html.erb",
          "app/views/home/index.html.erb"

        route_file = File.join(destination_root, "config/routes.rb")
        if File.exist?(route_file)
          content = File.read(route_file)
          unless content.include?("root")
            route 'root "home#index"'
          end
        end
      end

      # 14. Create README
      def create_readme
        template "README.md.erb", "README.md"
      end

      # 15. Create database.yml.example
      def create_database_sample
        db_config = File.join(destination_root, "config/database.yml")
        if File.exist?(db_config)
          copy_file db_config, "config/database.yml.example"
        end
      end

      # 16. Post-install message
      def show_post_install
        say ""
        say "Your Rails app is ready!", :green
        say ""
        say "Manual steps:", :yellow
        say "  1. bin/rails generate solid_errors:install"
        say "     (decline initializer overwrite to keep your config)"
        say "  2. bin/rails db:migrate"
        say "  3. Set credentials: bin/rails credentials:edit"
        say "     backstage:"
        say "       username: your_user"
        say "       password: your_password"
        say "  4. Start the app: bin/dev"
        if options[:auth] != "none"
          say ""
          say "Authentication (#{options[:auth]}):", :yellow
          say "  - Run bin/rails db:migrate if you haven't already"
          say "  - Visit /registrations/new to sign up" if options[:auth] == "registration"
          say "  - Visit /session/new to sign in"
        end
        say ""
      end

      private

      def rails_app?
        File.exist?(File.join(destination_root, "bin/rails"))
      end

      def configure_development
        dev_file = File.join(destination_root, "config/environments/development.rb")
        return unless File.exist?(dev_file)

        content = File.read(dev_file)

        unless content.include?("letter_opener")
          inject_into_file "config/environments/development.rb",
            before: /^end/ do
            <<~RUBY.indent(2)

              # Use letter_opener for email delivery
              config.action_mailer.delivery_method = :letter_opener
              config.action_mailer.perform_deliveries = true
              config.action_mailer.default_url_options = {host: "localhost", port: #{options[:port]}}
            RUBY
          end
        end
      end

      def configure_production
        prod_file = File.join(destination_root, "config/environments/production.rb")
        return unless File.exist?(prod_file)

        content = File.read(prod_file)

        unless content.include?("APPLICATION_HOST")
          inject_into_file "config/environments/production.rb",
            before: /^end/ do
            <<~RUBY.indent(2)

              # Set host for URL generation
              config.action_mailer.default_url_options = {host: ENV.fetch("APPLICATION_HOST", "example.com")}
            RUBY
          end
        end
      end
    end
  end
end
