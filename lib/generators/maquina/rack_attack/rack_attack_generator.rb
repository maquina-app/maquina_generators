require "rails/generators"

module Maquina
  module Generators
    class RackAttackGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

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

        run "bundle install", capture: true
      end

      # 4. Post-install message
      def show_post_install
        say ""
        say "Rack::Attack has been installed!", :green
        say ""
        say "Default protections enabled:", :yellow
        say "  - Blocklist: PHP files, WordPress paths, sensitive files, scanner targets"
        say "  - Safelist: localhost (127.0.0.1, ::1)"
        say "  - Throttle: 300 req/5min per IP, 5 login attempts/20s per IP"
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
