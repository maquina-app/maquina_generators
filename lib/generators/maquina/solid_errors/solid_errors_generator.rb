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
      class_option :agent, type: :boolean, default: false,
        desc: "Generate read-only AI-agent triage tooling (bin/failures + stdio MCP server)"
      class_option :mcp_http, type: :boolean, default: false,
        desc: "Also expose the MCP server over HTTP behind backstage auth (implies --agent; internet-exposed)"
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

      # 4. Enrich job failures with job context (always — benefits the dashboard
      #    too, not just the agent). On Solid Queue >= 1.0.2 a failed job's
      #    exception already flows to the Rails error reporter that Solid Errors
      #    subscribes to; this only attaches the job class/arguments/id to that
      #    report so a job failure is distinguishable and replayable.
      def configure_application_job
        job_path = "app/jobs/application_job.rb"
        full_path = File.join(destination_root, job_path)
        return unless File.exist?(full_path)
        return if File.read(full_path).include?("Rails.error.set_context")

        inject_into_class job_path, "ApplicationJob", <<~RUBY
          # Attach job context to errors reported to Rails.error so background-job
          # failures are distinguishable from request failures in Solid Errors,
          # and carry replayable arguments. Sets context only and lets Solid
          # Queue's built-in reporting forward the exception (reported once).
          #
          # If your Solid Queue version does not propagate this context to its
          # report, fall back to rescuing in the block, reporting explicitly with
          # `Rails.error.report(e, handled: false)`, and RE-RAISING (re-raising is
          # required: it preserves the failed_execution record and retries).
          around_perform do |job, block|
            Rails.error.set_context(
              active_job: job.class.name,
              arguments: job.arguments,
              job_id: job.job_id,
              queue_name: job.queue_name
            )
            block.call
          end
        RUBY
      end

      # 5. Add gem to Gemfile
      def add_gem
        gemfile_path = File.join(destination_root, "Gemfile")
        return unless File.exist?(gemfile_path)

        content = File.read(gemfile_path)
        unless content.include?('gem "solid_errors"')
          append_to_file "Gemfile", "\ngem \"solid_errors\"\n"
        end

        if agent? && !content.include?('gem "mcp"')
          append_to_file "Gemfile", "\ngem \"mcp\"\n"
        end
      end

      # 6. Routes
      def add_route
        mount_path = "#{options[:prefix]}/solid_errors"

        route "mount SolidErrors::Engine, at: \"#{mount_path}\""
      end

      # 7. Admin navigation
      def create_admin_navigation
        nav_path = "app/views/layouts/_admin_navigation.html.erb"
        return if File.exist?(File.join(destination_root, nav_path))

        template "app/views/layouts/_admin_navigation.html.erb.tt", nav_path
      end

      # 8. Layout
      def copy_layout
        copy_file "app/views/layouts/solid_errors/application.html.erb",
          "app/views/layouts/solid_errors/application.html.erb"
      end

      # 9. Stimulus controllers
      def copy_stimulus_controllers
        copy_file "app/javascript/controllers/clipboard_controller.js",
          "app/javascript/controllers/clipboard_controller.js"
        copy_file "app/javascript/controllers/backtrace_filter_controller.js",
          "app/javascript/controllers/backtrace_filter_controller.js"
      end

      # 10. Custom views
      def copy_views
        return unless options[:copy_views]

        view_files.each do |view|
          copy_file view, view
        end
      end

      # 11. AI-agent triage tooling (opt-in). Read-only query/triage layer over
      #     the errors store, a bin/ runner, and a stdio MCP server. Resolution
      #     stays a human action in the Backstage dashboards.
      def create_agent_files
        return unless agent?

        agent_files.each do |file|
          copy_file file, file
        end

        copy_file "bin/failures", "bin/failures"
        copy_file "bin/failures-mcp", "bin/failures-mcp"
        chmod "bin/failures", 0o755
        chmod "bin/failures-mcp", 0o755
      end

      # 12. MCP-over-HTTP endpoint (opt-in, internet-exposed). Mounts the same
      #     read-only tool surface behind the existing backstage Basic Auth so a
      #     developer can query a deployed app's failures from their machine.
      def create_mcp_http_controller
        return unless options[:mcp_http]

        template "app/controllers/failures_mcp_controller.rb.tt",
          "app/controllers/failures_mcp_controller.rb"

        route %(match "#{options[:prefix]}/failures/mcp", ) +
          %(to: "failures_mcp#handle", via: %i[get post delete])
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
        say "Job failures: app/jobs/application_job.rb now tags reported errors with", :yellow
        say "  job class, arguments, and id so background-job failures show up in the"
        say "  Solid Errors dashboard with replayable context (Solid Queue >= 1.0.2)."
        say ""

        show_agent_post_install if agent?
        show_mcp_http_post_install if options[:mcp_http]
      end

      private

      def agent?
        options[:agent] || options[:mcp_http]
      end

      def show_agent_post_install
        say "AI-agent triage tooling (read-only):", :green
        say ""
        say "  bin/failures overview                 # unresolved errors as JSON"
        say "  bin/failures top [limit]              # most frequent unresolved"
        say "  bin/failures exception <fingerprint>  # full detail + backtrace"
        say ""
        say "  Register the local stdio MCP server with Claude Code (app root):", :yellow
        say "    claude mcp add failures -- bin/failures-mcp"
        say ""
        say "  Query a DEPLOYED app from your machine (server runs where the", :yellow
        say "  errors DB lives — pick what matches your deploy):"
        say "    ssh:    claude mcp add failures -- ssh user@host 'cd /app && bin/failures-mcp'"
        say "    docker: claude mcp add failures -- ssh user@host 'docker exec -i <container> bin/failures-mcp'"
        say "    kamal:  claude mcp add failures -- kamal app exec -i --reuse \"bin/failures-mcp\""
        say "    offline: copy storage/production_errors.sqlite3 down, run bin/failures locally"
        say ""
        say "  Review app/agents/error_redactor.rb — it masks sensitive keys", :yellow
        say "  (passwords, tokens, email, ...) before any data reaches the agent."
        say ""
      end

      def show_mcp_http_post_install
        say "MCP-over-HTTP endpoint (internet-exposed, read-only):", :green
        say ""
        say "  Mounted at #{options[:prefix]}/failures/mcp behind backstage Basic Auth."
        say "  It self-disables (503) until backstage credentials are set."
        say ""
        say "  Register from your machine:", :yellow
        say "    claude mcp add --transport http failures \\"
        say "      https://yourapp.com#{options[:prefix]}/failures/mcp \\"
        say "      --header \"Authorization: Basic $(echo -n user:pass | base64)\""
        say ""
        say "  SECURITY: this serves redacted-but-sensitive failure data over the", :red
        say "  internet. Enable only where intended and put it behind an IP allowlist/VPN."
        say ""
      end

      def rails_app?
        File.exist?(File.join(destination_root, "bin/rails"))
      end

      def view_files
        views_dir = File.join(self.class.source_root, "app/views/solid_errors")
        Dir.glob("**/*.erb", base: views_dir).map do |file|
          File.join("app/views/solid_errors", file)
        end
      end

      def agent_files
        agents_dir = File.join(self.class.source_root, "app/agents")
        Dir.glob("**/*.rb", base: agents_dir).map do |file|
          File.join("app/agents", file)
        end
      end
    end
  end
end
