require "rails/generators"
require "generators/maquina/rack_attack/rack_attack_generator"

module Maquina
  module Generators
    class SecurityGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      ENVIRONMENTS = %w[development test production].freeze
      # The end of the Jobs tab in the generated admin navigation: a new tab
      # goes after it.
      JOBS_TAB_END = %r{<span>Jobs</span>\n\s*<% end %>\n}

      class_option :prefix, type: :string, required: true,
        desc: "Base path prefix (e.g. /admin)"
      class_option :user_env_var, type: :string, default: "SECURITY_USER",
        desc: "Environment variable for HTTP auth username"
      class_option :password_env_var, type: :string, default: "SECURITY_PASSWORD",
        desc: "Environment variable for HTTP auth password"
      class_option :login_path, type: :string, default: "/session",
        desc: "Path whose POSTs the login throttle counts"
      class_option :copy_views, type: :boolean, default: true,
        desc: "Copy the Security dashboard views to the host app"
      class_option :quiet, type: :boolean, default: false,
        desc: "Suppress post-install instructions"

      # 1. BackstageController
      def create_backstage_controller
        backstage_path = "app/controllers/backstage_controller.rb"
        return if File.exist?(File.join(destination_root, backstage_path))

        template "app/controllers/backstage_controller.rb.tt", backstage_path
      end

      # 2. Rack::Attack rules (maquina:rack_attack) and the recording subscriber
      def install_rack_attack
        initializer = File.join(destination_root, "config/initializers/rack_attack.rb")
        current = File.exist?(initializer) ? File.read(initializer) : nil

        unless current&.include?("def self.banned?")
          @replaced_rack_attack = !current.nil?
          invoke RackAttackGenerator, [],
            login_path: options[:login_path], quiet: true, force: @replaced_rack_attack
        end

        copy_file "config/initializers/rack_attack_events.rb",
          "config/initializers/rack_attack_events.rb"
      end

      # 3. Models
      def create_models
        %w[record abuse_event abuse_report].each do |name|
          copy_file "app/models/security/#{name}.rb", "app/models/security/#{name}.rb"
        end
      end

      # 4. Schema for the security database
      def create_schema
        template "db/security_schema.rb.tt", "db/security_schema.rb"
      end

      # 5. database.yml (and its example) gain a security database
      def configure_database
        %w[config/database.yml config/database.yml.example].each do |path|
          add_security_database(path)
        end
      end

      # 6. Daily purge of expired events
      def add_recurring_purge
        path = File.join(destination_root, "config/recurring.yml")
        content = File.exist?(path) ? File.read(path) : ""
        return if content.include?("purge_abuse_events")

        if content.match?(/^production:\n/)
          inject_into_file "config/recurring.yml", recurring_entry, after: /^production:\n/
        else
          @recurring_pending = true
        end
      end

      # 7. Add gem to Gemfile
      def add_gem
        gemfile_path = File.join(destination_root, "Gemfile")
        if File.exist?(gemfile_path)
          content = File.read(gemfile_path)
          unless content.include?('gem "rack-attack"')
            append_to_file "Gemfile", "\ngem \"rack-attack\"\n"
          end
        end
      end

      # 8. Controller
      def create_controller
        template "app/controllers/backstage/security_controller.rb.tt",
          "app/controllers/backstage/security_controller.rb"
      end

      # 9. Routes
      def add_route
        route %(get "#{options[:prefix]}/security", to: "backstage/security#show", as: :backstage_security)
      end

      # 10. Admin navigation
      def create_admin_navigation
        nav_path = "app/views/layouts/_admin_navigation.html.erb"
        full_path = File.join(destination_root, nav_path)

        unless File.exist?(full_path)
          template "app/views/layouts/_admin_navigation.html.erb.tt", nav_path
          return
        end

        content = File.read(full_path)
        return if content.include?("#{options[:prefix]}/security")

        if content.match?(JOBS_TAB_END)
          inject_into_file nav_path, security_tab, after: JOBS_TAB_END
        else
          @nav_pending = true
        end
      end

      # 11. Layout
      def copy_layout
        copy_file "app/views/layouts/backstage/security.html.erb",
          "app/views/layouts/backstage/security.html.erb"
      end

      # 11b. Backstage dashboard — the Overview tab of the admin navigation.
      #      Shared with solid_errors and mission_control_jobs, so every step
      #      is guarded for when more than one of them runs.
      def create_backstage_dashboard
        install_backstage_dashboard
      end

      # 12. Views
      def copy_views
        return unless options[:copy_views]

        view_files.each { |f| copy_file f, f }
      end

      # 13. Bundle install
      def run_bundle_install
        return unless rails_app?

        Bundler.with_unbundled_env do
          system("bundle install", chdir: destination_root)
        end
      end

      # 14. Post-install message
      def show_post_install
        return if options[:quiet]

        say ""
        say "Security dashboard has been installed!", :green
        say ""
        say "Next steps:", :yellow
        say "  - Create the security database: bin/rails db:prepare"
        say "  - Set credentials: bin/rails credentials:edit"
        say "    backstage:"
        say "      username: your_user"
        say "      password: your_password"
        say "  - Or set ENV vars: #{options[:user_env_var]}, #{options[:password_env_var]}"
        say "  - Visit #{options[:prefix]}/security"
        if @replaced_rack_attack
          say ""
          say "config/initializers/rack_attack.rb was replaced with the maquina:rack_attack rules.", :yellow
        end
        if @recurring_pending
          say ""
          say "Add to config/recurring.yml under your production (or shared) key:", :yellow
          say recurring_entry
        end
        if @database_pending
          say ""
          say "Add a `security` database to each environment in config/database.yml (migrations_paths: db/security_migrate).", :yellow
        end
        if @nav_pending
          say ""
          say "Add a Security tab linking to #{options[:prefix]}/security in app/views/layouts/_admin_navigation.html.erb", :yellow
        end
        say ""
      end

      private

      def rails_app?
        File.exist?(File.join(destination_root, "bin/rails"))
      end

      # Idempotent install of the shared backstage dashboard (controller, layout,
      # prefix-aware view, and the prefix-root route). Safe to run from this
      # generator, solid_errors and mission_control_jobs.
      def install_backstage_dashboard
        unless File.exist?(File.join(destination_root, "app/controllers/backstage_dashboard_controller.rb"))
          copy_file "app/controllers/backstage_dashboard_controller.rb",
            "app/controllers/backstage_dashboard_controller.rb"
        end

        unless File.exist?(File.join(destination_root, "app/views/layouts/admin.html.erb"))
          copy_file "app/views/layouts/admin.html.erb", "app/views/layouts/admin.html.erb"
        end

        unless File.exist?(File.join(destination_root, "app/views/backstage_dashboard/index.html.erb"))
          template "app/views/backstage_dashboard/index.html.erb.tt",
            "app/views/backstage_dashboard/index.html.erb"
        end

        routes_path = File.join(destination_root, "config/routes.rb")
        if File.exist?(routes_path) && !File.read(routes_path).include?("backstage_dashboard#index")
          route %(get "#{options[:prefix]}" => "backstage_dashboard#index", as: :backstage_dashboard)
        end
      end

      def view_files
        views_dir = File.join(self.class.source_root, "app/views/backstage/security")
        Dir.glob("**/*.erb", base: views_dir).map do |file|
          File.join("app/views/backstage/security", file)
        end
      end

      def recurring_entry
        <<~YAML.gsub(/^/, "  ")
          purge_abuse_events:
            command: "Security::AbuseEvent.expired.delete_all"
            schedule: every day at 4am
        YAML
      end

      def security_tab
        <<-ERB

          <%= link_to "#{options[:prefix]}/security",
              class: "inline-flex items-center gap-1.5 whitespace-nowrap px-1 py-3 text-sm font-medium \#{request.path.start_with?('#{options[:prefix]}/security') ? 'border-b-2 border-primary text-primary' : 'text-muted-foreground hover:text-foreground'}" do %>
            <%= icon_for(:slash, class: "size-4") %>
            <span>Security</span>
          <% end %>
        ERB
      end

      # Appends a `security:` entry to each environment. A single-database
      # SQLite environment (Rails' default for development and test) is first
      # nested under `primary:`, which is the same database under a name.
      # Any other adapter is left for the app to configure.
      def add_security_database(path)
        full_path = File.join(destination_root, path)
        return unless File.exist?(full_path)

        ENVIRONMENTS.each do |env|
          content = File.read(full_path)
          block = content[/^#{env}:\n(?:(?: .*)?\n)*?(?=\n*(?:^\S|\z))/]
          next if block.nil? || block.include?("  security:")

          if block.include?("  primary:")
            inject_into_file path, security_entry(env), after: block
          elsif content.include?("adapter: sqlite3")
            primary = block.sub(/\A#{env}:\n/, "").gsub(/^(?=.)/, "  ")
            gsub_file(path, block) { "#{env}:\n  primary:\n#{primary}#{security_entry(env)}" }
          else
            @database_pending = true
          end
        end
      end

      def security_entry(env)
        <<~YAML.gsub(/^/, "  ")
          security:
            <<: *default
            database: storage/#{env}_security.sqlite3
            migrations_paths: db/security_migrate
        YAML
      end
    end
  end
end
