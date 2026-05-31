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

        remove_gems = ["rubocop-rails-omakase"]
        # standard >= 1.54: avoids the inoperative placeholder releases
        # (1.34.0.1 / 1.35.0.1) whose too-loose `rubocop ~> 1.62` requirement
        # makes bundler backtrack onto them and pair them with an incompatible
        # rubocop, so the `standard` binary refuses to run.
        #
        # standard.rb runs through the generated .rubocop.yml (see
        # create_config_files) — that file is standard.rb's runner bridge, not
        # custom RuboCop rules, so it ships even though guidance says "no
        # .rubocop.yml".
        dev_gems = {"brakeman" => nil, "bundle-audit" => nil, "letter_opener" => nil, "standard" => ">= 1.54"}
        runtime_gems = {"rails-i18n" => nil, "maquina-components" => nil}
        production_gems = {"aws-sdk-s3" => nil}

        remove_gems.each do |gem_name|
          gsub_file "Gemfile", /^\s*gem\s+["']#{gem_name}["'].*\n/, ""
        end

        dev_gems.each do |gem_name, version|
          next if content.include?("gem \"#{gem_name}\"")
          append_to_file "Gemfile", "\n#{gem_line(gem_name, version, group: :development)}\n"
        end

        runtime_gems.each do |gem_name, version|
          next if content.include?("gem \"#{gem_name}\"")
          append_to_file "Gemfile", "\n#{gem_line(gem_name, version)}\n"
        end

        production_gems.each do |gem_name, version|
          next if content.include?("gem \"#{gem_name}\"")
          append_to_file "Gemfile", "\n#{gem_line(gem_name, version, group: :production)}\n"
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

      # 4. Initializers
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

        unless content.include?("solid_queue")
          inject_into_file "config/application.rb",
            after: /class Application < Rails::Application\n/ do
            <<~RUBY.indent(4)

              # Use Solid Queue as the Active Job backend in all environments except test
              config.active_job.queue_adapter = :solid_queue unless Rails.env.test?
              config.solid_queue.connects_to = {database: {writing: :queue}}
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

        if content.include?('class="container mx-auto mt-28 px-5 flex"')
          gsub_file "app/views/layouts/application.html.erb",
            '<main class="container mx-auto mt-28 px-5 flex">',
            "<main>"
        end
      end

      # 11. Install authentication
      def install_authentication
        return unless rails_app?

        case options[:auth]
        when "clave"
          generate "maquina:clave", "--quiet"
        when "registration"
          generate "maquina:registration", "--quiet"
        end
      end

      # 12. Install maquina generators
      def install_maquina_generators
        return unless rails_app?

        generate "maquina:rack_attack", "--quiet"
        generate "maquina:mission_control_jobs", "--prefix", options[:prefix], "--quiet"
        generate "maquina:solid_errors", "--prefix", options[:prefix], "--quiet"

        Bundler.with_unbundled_env do
          system("bin/rails generate solid_queue:install", chdir: destination_root)
          system("bin/rails generate solid_errors:install", chdir: destination_root)
          system("bin/rails generate solid_cache:install", chdir: destination_root)
          system("bin/rails generate solid_cable:install", chdir: destination_root)
          system("bin/rails generate maquina_components:install", chdir: destination_root)
        end
      end

      # 13. Restore custom layouts overwritten by gem installers
      def restore_custom_layouts
        return unless rails_app?

        solid_errors_layout = File.expand_path(
          "../solid_errors/templates/app/views/layouts/solid_errors/application.html.erb",
          __dir__
        )

        if File.exist?(solid_errors_layout)
          create_file "app/views/layouts/solid_errors/application.html.erb",
            File.read(solid_errors_layout), force: true
        end
      end

      # 14. Configure multiple databases (after installers so we overwrite their database.yml)
      def configure_databases
        template "config/database.yml.tt", "config/database.yml", force: true
      end

      # 15. Create home page
      def create_home_page
        template "app/controllers/home_controller.rb",
          "app/controllers/home_controller.rb"
        template "app/views/home/index.html.erb",
          "app/views/home/index.html.erb"

        route_file = File.join(destination_root, "config/routes.rb")
        if File.exist?(route_file)
          content = File.read(route_file)
          unless content.match?(/^\s*root\s/)
            route 'root "home#index"'
          end
        end
      end

      # 16. Create README
      def create_readme
        template "README.md.erb", "README.md"
      end

      # 17. Create database.yml.example
      def create_database_sample
        db_config = File.join(destination_root, "config/database.yml")
        if File.exist?(db_config)
          copy_file db_config, "config/database.yml.example"
        end
      end

      # 18. Restore database.yml from its example in bin/setup. config/database.yml
      #     is gitignored (it differs per environment), so a fresh clone has only
      #     the committed example — bin/setup must copy it before db:prepare.
      def configure_bin_setup
        setup_file = File.join(destination_root, "bin/setup")
        return unless File.exist?(setup_file)
        return if File.read(setup_file).include?("config/database.yml.example")

        inject_into_file "bin/setup",
          after: %r{system\("bundle check"\) \|\| system!\("bundle install"\)\n} do
          <<~RUBY.indent(2)

            # config/database.yml is gitignored; restore it from the committed example
            unless File.exist?("config/database.yml")
              puts "\\n== Copying config/database.yml =="
              FileUtils.cp "config/database.yml.example", "config/database.yml"
            end
          RUBY
        end
      end

      # 19. Restore database.yml from its example in CI. Without it, the test job
      #     boots with no database.yml and every Rails task fails. Only touched
      #     when the host app already has a GitHub Actions workflow.
      def configure_ci
        ci_file = File.join(destination_root, ".github/workflows/ci.yml")
        return unless File.exist?(ci_file)
        return if File.read(ci_file).include?("config/database.yml.example")

        inject_into_file ".github/workflows/ci.yml",
          before: /^      - name: Run tests$/ do
          <<~YAML.indent(6)
            - name: Prepare database config
              run: cp config/database.yml.example config/database.yml
          YAML
        end
      end

      # 20. Run all migrations
      def run_migrations
        return unless rails_app?

        Bundler.with_unbundled_env do
          system("bin/rails db:prepare", chdir: destination_root)
        end
      end

      # 21. Post-install message
      def show_post_install
        say ""
        say "=" * 60, :green
        say "Your Rails app is ready!", :green
        say "=" * 60, :green
        say ""
        say "Next steps:", :yellow
        say "  1. Set credentials: bin/rails credentials:edit"
        say "     backstage:"
        say "       username: your_user"
        say "       password: your_password"
        say "  2. Start the app: bin/dev"
        say ""
        say "Installed components:", :yellow
        say "  - Rack::Attack: rate limiting and blocklists (config/initializers/rack_attack.rb)"
        say "  - Solid Queue: background jobs (config/solid_queue.yml)"
        say "  - Mission Control Jobs: job dashboard at #{options[:prefix]}/mission_control_jobs"
        say "  - Solid Errors: error tracking at #{options[:prefix]}/solid_errors"
        say "  - Maquina Components: UI components"
        if options[:auth] != "none"
          say ""
          say "Authentication (#{options[:auth]}):", :yellow
          say "  - Visit /session/new to sign in"
          say "  - Visit /registrations/new to sign up" if options[:auth] == "registration"
          say "  - Visit /registration/new to sign up" if options[:auth] == "clave"
          say "  - Customize: app/controllers/concerns/authentication.rb"
          say "  - Locales: config/locales/"
        end
        say ""
      end

      private

      def gem_line(name, version, group: nil)
        line = "gem \"#{name}\""
        line << ", \"#{version}\"" if version
        line << ", group: :#{group}" if group
        line
      end

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
