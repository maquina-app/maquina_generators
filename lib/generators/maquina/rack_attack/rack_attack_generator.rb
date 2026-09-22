require "rails/generators"

module Maquina
  module Generators
    class RackAttackGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :login_path, type: :string, default: "/session",
        desc: "Path whose POSTs the login throttle counts"
      class_option :quiet, type: :boolean, default: false,
        desc: "Suppress post-install instructions"

      # 1. Initializer
      def create_initializer
        template "config/initializers/rack_attack.rb.tt",
          "config/initializers/rack_attack.rb"
      end

      # 2. Add gem to Gemfile
      def add_gem
        gemfile_path = File.join(destination_root, "Gemfile")
        if File.exist?(gemfile_path)
          content = File.read(gemfile_path)
          unless content.include?('gem "rack-attack"')
            append_to_file "Gemfile", "\ngem \"rack-attack\"\n"
          end
        end
      end

      # 3. Bundle install
      def run_bundle_install
        return unless rails_app?

        Bundler.with_unbundled_env do
          system("bundle install", chdir: destination_root)
        end
      end

      # 4. Post-install message
      def show_post_install
        return if options[:quiet]

        say ""
        say "Rack::Attack has been installed!", :green
        say ""
        say "Default protections enabled:", :yellow
        say "  - Scanner ban: 3 scanner paths (PHP, WordPress, dotfiles, backup archives) in 10 min bans the IP for 7 days"
        say "  - Flood ban: 600 requests in 5 min bans the IP for 1 day"
        say "  - Throttle: 300 req/5min per IP, 5 POST #{options[:login_path]}/20s per IP"
        say "  - Safelist: localhost (127.0.0.1, ::1)"
        say "  - Every refusal logged as an [ATTACK] line"
        say ""
        say "Customize rules in config/initializers/rack_attack.rb"
        say ""
      end

      private

      def rails_app?
        File.exist?(File.join(destination_root, "bin/rails"))
      end
    end
  end
end
