require "rails/generators"
require "rails/generators/migration"

module Maquina
  module Generators
    class CspReportsGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      THROTTLE_LIMIT = 100
      THROTTLE_PERIOD = "5.minutes"
      # Rails' default nonce generator, empty for a request without a session.
      SESSION_NONCE = "->(request) { request.session.id.to_s }"
      POLICY_BLOCK = /^  config\.content_security_policy do \|policy\|\n/
      # The general throttle's exemptions, in the two shapes maquina:rack_attack
      # has shipped: a start_with? list, and a STATIC_FILE_PREFIXES word array.
      COUNTED_IP_EXEMPTIONS = /req\.path\.start_with\?\("\/assets", "\/rails\/active_storage"/
      STATIC_FILE_PREFIXES = /(STATIC_FILE_PREFIXES = %w\[)([^\]]*)(\])/
      SECURITY_PAGE_END = /\n<\/div>\n\z/

      class_option :path, type: :string, default: "/csp-reports",
        desc: "Path browsers post violation reports to"
      class_option :quiet, type: :boolean, default: false,
        desc: "Suppress post-install instructions"

      def self.next_migration_number(dirname)
        current = Time.now.utc.strftime("%Y%m%d%H%M%S")
        existing = Dir.glob("#{dirname}/[0-9]*_*.rb").map { |f| File.basename(f).split("_", 2).first }.max
        (existing && existing >= current) ? existing.succ : current
      end

      # 1. maquina:security owns the database the reports go in.
      def require_security_database
        return if File.exist?(File.join(destination_root, "db/security_schema.rb"))

        raise Thor::Error, "maquina:csp_reports stores reports in the `security` database. Run `rails g maquina:security --prefix /admin` first."
      end

      # 2. Models
      def create_models
        copy_file "app/models/security/csp_violation.rb", "app/models/security/csp_violation.rb"
        copy_file "app/models/security/csp_violation_report.rb", "app/models/security/csp_violation_report.rb"
      end

      # 3. Controller and route
      def create_controller
        copy_file "app/controllers/csp_reports_controller.rb", "app/controllers/csp_reports_controller.rb"
        route %(post "#{options[:path]}", to: "csp_reports#create", as: :csp_reports)
      end

      # 4. The table: a migration for an existing security database, the schema
      #    for a fresh one (db:prepare loads the schema only on create).
      def create_table
        return if File.read(schema_path).include?(%("csp_violations"))

        migration_template "db/create_csp_violations.rb.tt", "db/security_migrate/create_csp_violations.rb"
        version = Dir.glob(File.join(destination_root, "db/security_migrate/*_create_csp_violations.rb"))
          .map { |f| File.basename(f).split("_", 2).first }.max
        gsub_file "db/security_schema.rb", /define\(version: [\d_]+\)/, "define(version: #{version_with_underscores(version)})"
        inject_into_file "db/security_schema.rb", csp_violations_table, before: /^end\s*\z/
      end

      # 5. The policy reports to the endpoint, and anonymous requests get a nonce.
      def configure_content_security_policy
        path = "config/initializers/content_security_policy.rb"
        content = File.exist?(File.join(destination_root, path)) ? File.read(File.join(destination_root, path)) : ""

        if content.include?("report_uri")
          @report_uri_pending = !content.include?(%(report_uri "#{options[:path]}"))
        elsif content.match?(POLICY_BLOCK)
          inject_into_file path, report_uri_line, after: POLICY_BLOCK
        else
          @report_uri_pending = true
        end

        if content.include?(SESSION_NONCE)
          gsub_file path, SESSION_NONCE, "->(request) { request.session.id.to_s.presence || SecureRandom.base64(16) }"
        end
      end

      # 6. Rack::Attack: out of the general throttle, capped on its own.
      def configure_rack_attack
        path = "config/initializers/rack_attack.rb"
        full_path = File.join(destination_root, path)
        return @rack_attack_pending = true unless File.exist?(full_path)

        content = File.read(full_path)
        return if content.include?(%("csp/ip"))

        if content.match?(COUNTED_IP_EXEMPTIONS)
          # The match stops before the call's closing paren, which stays in place.
          gsub_file path, COUNTED_IP_EXEMPTIONS, 'req.path.start_with?("/assets", "/rails/active_storage", ' + %("#{options[:path]}")
        elsif content.match?(STATIC_FILE_PREFIXES)
          gsub_file path, STATIC_FILE_PREFIXES, "\\1\\2 #{options[:path]}\\3"
        else
          @rack_attack_pending = true
        end

        append_to_file path, csp_throttle
      end

      # 7. Daily purge
      def add_recurring_purge
        path = File.join(destination_root, "config/recurring.yml")
        content = File.exist?(path) ? File.read(path) : ""
        return if content.include?("purge_csp_violations")

        if content.match?(/^production:\n/)
          inject_into_file "config/recurring.yml", recurring_entry, after: /^production:\n/
        else
          @recurring_pending = true
        end
      end

      # 8. Security page section
      def add_security_page_section
        copy_file "app/views/backstage/security/_csp_violations.html.erb",
          "app/views/backstage/security/_csp_violations.html.erb"

        page = "app/views/backstage/security/show.html.erb"
        full_path = File.join(destination_root, page)
        content = File.exist?(full_path) ? File.read(full_path) : ""
        return if content.include?("backstage/security/csp_violations")

        if content.match?(SECURITY_PAGE_END)
          inject_into_file page, security_page_section, before: SECURITY_PAGE_END
        else
          @page_pending = true
        end
      end

      # 9. Post-install message
      def show_post_install
        return if options[:quiet]

        say ""
        say "Content Security Policy reports are set up at POST #{options[:path]}.", :green
        say ""
        say "Next steps:", :yellow
        say "  - Add the table: bin/rails db:migrate (db:prepare on deploy)"
        say "  - Watch the Security page while the policy is report-only, then set"
        say "    content_security_policy_report_only = false to enforce it."
        if @report_uri_pending
          say ""
          say "Point the policy at the endpoint in config/initializers/content_security_policy.rb:", :yellow
          say "  #{report_uri_line.strip}"
        end
        if @rack_attack_pending
          say ""
          say "Exempt #{options[:path]} from the general throttle in config/initializers/rack_attack.rb and add:", :yellow
          say csp_throttle
        end
        if @recurring_pending
          say ""
          say "Add to config/recurring.yml under your production (or shared) key:", :yellow
          say recurring_entry
        end
        if @page_pending
          say ""
          say "Render the section on the Security page:", :yellow
          say security_page_section
        end
        say ""
      end

      private

      def schema_path = File.join(destination_root, "db/security_schema.rb")

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end

      def version_with_underscores(version)
        version.sub(/\A(\d{4})(\d{2})(\d{2})(\d{6})\z/, '\1_\2_\3_\4')
      end

      def report_uri_line
        %(    # Violations go to CspReportsController (maquina:csp_reports). report-uri\n) +
          %(    # alone: adding report-to switches Chrome to the batched Reporting API.\n) +
          %(    policy.report_uri "#{options[:path]}"\n)
      end

      def csp_throttle
        <<~RUBY

          # Content Security Policy reports (maquina:csp_reports): exempt from the
          # general throttle above — one page with a dozen violations would spend a
          # reader's budget — and capped on their own.
          Rack::Attack.throttle("csp/ip", limit: #{THROTTLE_LIMIT}, period: #{THROTTLE_PERIOD}) do |req|
            (req.env["action_dispatch.remote_ip"]&.to_s || req.ip) if req.path == "#{options[:path]}" && req.post?
          end
        RUBY
      end

      def recurring_entry
        <<~YAML.gsub(/^/, "  ")
          purge_csp_violations:
            command: "Security::CspViolation.expired.delete_all"
            schedule: every day at 4:30am
        YAML
      end

      def security_page_section
        %(\n\n  <%= render "backstage/security/csp_violations", report: Security::CspViolationReport.new %>)
      end

      def csp_violations_table
        <<~RUBY.gsub(/^(?=.)/, "  ")

          create_table "csp_violations", force: :cascade do |t|
            t.integer "column_number"
            t.datetime "created_at", null: false
            t.string "blocked_uri"
            t.string "disposition"
            t.string "document_uri"
            t.string "effective_directive", null: false
            t.string "ip"
            t.integer "line_number"
            t.string "sample"
            t.string "source_file"
            t.string "user_agent"
            t.index ["created_at"], name: "index_csp_violations_on_created_at"
            t.index ["effective_directive", "created_at"], name: "index_csp_violations_on_effective_directive_and_created_at"
          end
        RUBY
      end
    end
  end
end
