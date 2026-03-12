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
      class_option :copy_views, type: :boolean, default: true,
        desc: "Copy custom Solid Errors views to the host app"
      class_option :quiet, type: :boolean, default: false,
        desc: "Suppress post-install instructions"

      # 1. BackstageController
      def create_backstage_controller
        backstage_path = "app/controllers/backstage_controller.rb"
        return if File.exist?(File.join(destination_root, backstage_path))

        template "app/controllers/backstage_controller.rb.tt", backstage_path
      end

      # 2. Helper
      def create_helper
        copy_file "app/helpers/solid_errors_helper.rb",
          "app/helpers/solid_errors_helper.rb"
      end

      # 3. Initializer
      def create_initializer
        template "config/initializers/solid_errors.rb.tt",
          "config/initializers/solid_errors.rb"
      end

      # 4. Add gem to Gemfile
      def add_gem
        gemfile_path = File.join(destination_root, "Gemfile")
        if File.exist?(gemfile_path)
          content = File.read(gemfile_path)
          unless content.include?('gem "solid_errors"')
            append_to_file "Gemfile", "\ngem \"solid_errors\"\n"
          end
        end
      end

      # 5. Routes
      def add_route
        mount_path = "#{options[:prefix]}/solid_errors"

        route "mount SolidErrors::Engine, at: \"#{mount_path}\""
      end

      # 6. Admin navigation
      def create_admin_navigation
        nav_path = "app/views/layouts/_admin_navigation.html.erb"
        return if File.exist?(File.join(destination_root, nav_path))

        template "app/views/layouts/_admin_navigation.html.erb.tt", nav_path
      end

      # 7. Layout
      def copy_layout
        copy_file "app/views/layouts/solid_errors/application.html.erb",
          "app/views/layouts/solid_errors/application.html.erb"
      end

      # 8. Stimulus controllers
      def copy_stimulus_controllers
        copy_file "app/javascript/controllers/clipboard_controller.js",
          "app/javascript/controllers/clipboard_controller.js"
        copy_file "app/javascript/controllers/backtrace_filter_controller.js",
          "app/javascript/controllers/backtrace_filter_controller.js"
      end

      # 9. Custom views
      def copy_views
        return unless options[:copy_views]

        view_files.each do |view|
          copy_file view, view
        end
      end

      # 10. Bundle install
      def run_bundle_install
        return unless rails_app?

        Bundler.with_unbundled_env do
          system("bundle install", chdir: destination_root)
        end
      end

      # 11. Post-install message
      def show_post_install
        return if options[:quiet]

        say ""
        say "Solid Errors has been installed!", :green
        say ""
        say "Next steps:", :yellow
        say "  1. bin/rails generate solid_errors:install"
        say "     (when prompted to overwrite the initializer, choose 'n' to keep your config)"
        say "  2. bin/rails db:migrate"
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

      def view_files
        views_dir = File.join(self.class.source_root, "app/views/solid_errors")
        Dir.glob("**/*.erb", base: views_dir).map do |file|
          File.join("app/views/solid_errors", file)
        end
      end
    end
  end
end
