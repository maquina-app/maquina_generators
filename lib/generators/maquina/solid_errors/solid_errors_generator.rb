require "rails/generators"

module Maquina
  module Generators
    class SolidErrorsGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :prefix, type: :string, required: true,
        desc: "Base path prefix (e.g. /admin)"
      class_option :user_env_var, type: :string, default: "SOLID_ERRORS_USER",
        desc: "Environment variable for HTTP auth username"
      class_option :password_env_var, type: :string, default: "SOLID_ERRORS_PASSWORD",
        desc: "Environment variable for HTTP auth password"

      # 1. BackstageController
      def create_backstage_controller
        backstage_path = "app/controllers/backstage_controller.rb"
        return if File.exist?(File.join(destination_root, backstage_path))

        template "app/controllers/backstage_controller.rb.tt", backstage_path
      end

      # 2. Initializer
      def create_initializer
        template "config/initializers/solid_errors.rb.tt",
          "config/initializers/solid_errors.rb"
      end

      # 3. Add gem to Gemfile
      def add_gem
        gemfile_path = File.join(destination_root, "Gemfile")
        if File.exist?(gemfile_path)
          content = File.read(gemfile_path)
          unless content.include?('gem "solid_errors"')
            append_to_file "Gemfile", "\ngem \"solid_errors\"\n"
          end
        end
      end

      # 4. Routes
      def add_route
        mount_path = "#{options[:prefix]}/solid_errors"

        route "mount SolidErrors::Engine, at: \"#{mount_path}\""
      end

      # 5. Bundle install
      def run_bundle_install
        return unless rails_app?

        run "bundle install", capture: true
      end

      # 6. Run solid_errors:install
      def run_gem_install
        return unless rails_app?

        run "bin/rails generate solid_errors:install", capture: true
      end

      # 7. Post-install message
      def show_post_install
        say ""
        say "Solid Errors has been installed!", :green
        say ""
        say "Next steps:", :yellow
        say "  1. bin/rails db:migrate"
        say ""
        say "Configuration:", :yellow
        say "  - Set credentials: bin/rails credentials:edit"
        say "    backstage:"
        say "      username: your_user"
        say "      password: your_password"
        say "  - Or set ENV vars: #{options[:user_env_var]}, #{options[:password_env_var]}"
        say ""
      end

      private

      def rails_app?
        File.exist?(File.join(destination_root, "bin/rails"))
      end
    end
  end
end
