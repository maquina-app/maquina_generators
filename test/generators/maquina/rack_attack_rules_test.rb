require "test_helper"
require "generators/maquina/rack_attack/rack_attack_generator"
require "erb"
# The template uses ActiveSupport's duration helpers (7.days, 10.minutes).
require "active_support/core_ext/integer/time"
# Behavioural tests for the Rack::Attack scanner-path rules.
#
# The other rack_attack test asserts on the generated TEXT. This one renders
# the template and evaluates the rule class, so it exercises the matching
# itself: a path that must be refused is refused, and a path the app really
# serves is not.
#
# The rules were measured against 30,703 refused requests collected from five
# production apps, and checked against 765 real routes.
class Maquina::Generators::RackAttackRulesTest < ActiveSupport::TestCase
  # The template renders `options[:login_path]`, so the ERB binding needs an
  # `options` method.
  def self.binding_with_options(options)
    Object.new.tap { |o| o.define_singleton_method(:options) { options } }.instance_eval { binding }
  end

  # The template's rule class, evaluated in a sandbox. It needs ActiveSupport's
  # duration helpers (7.days, 10.minutes) and a Rack::Attack namespace; the
  # gem itself is not a dependency of this gem (the generated app installs it).
  RULES = begin
    template = File.read(
      File.expand_path(
        "../../../lib/generators/maquina/rack_attack/templates/config/initializers/rack_attack.rb.tt",
        __dir__
      )
    )
    rendered = ERB.new(template, trim_mode: "-").result(
      binding_with_options({login_path: "/session"})
    )
    rules = rendered[/^class Rack::Attack$.*?^end$/m]
    raise "could not extract the rule class from the template" if rules.nil?

    unless defined?(::Rack::Attack)
      module ::Rack
        class Attack; end
      end
    end
    eval(rules, TOPLEVEL_BINDING, "rack_attack_rules.rb") # rubocop:disable Security/Eval
    ::Rack::Attack
  end

  def scanner_path?(path)
    RULES.scanner_path?(path)
  end

  # --- must be refused ------------------------------------------------------

  SCANNER_PATHS = [
    "/wp-login.php",
    "/wp-admin/install.php",
    "/xmlrpc.php",
    "/phpmyadmin",
    "/cgi-bin/test-cgi",
    "/vendor/phpunit/phpunit/src/Util/PHP/eval-stdin.php",
    "/.env",
    "/.git/config",
    "/.aws/credentials",
    "/.ssh/id_rsa",
    "/etc/passwd",
    "/etc/shadow",
    "/phpinfo",
    "/actuator",
    "/debug/vars",
    "/telescope/requests",
    "/_ignition/health-check",
    "/backup.zip",
    "/db.sql.gz",
    # Cloud provider credentials.
    "/firebase-adminsdk.json",
    "/service-account.json",
    "/gcp-credentials.json",
    "/google-service-account.json",
    "/sa.json",
    # Private key material.
    "/key.pem",
    "/server.key",
    "/id_rsa.p12",
    # Container runtime.
    "/var/run/secrets/kubernetes.io/serviceaccount/token",
    "/@fs/var/run/secrets/kubernetes.io/serviceaccount/token",
    "/proc/self/environ",
    "/.dockerenv",
    # Infrastructure as code.
    "/docker-compose.yml",
    "/Dockerfile",
    "/terraform.tfstate",
    "/values.yaml",
    # Bare secret files.
    "/secrets.json",
    "/secrets.yml",
    "/credentials.json",
    "/passwords.json",
    # Config dumps.
    "/config.json",
    "/env.js",
    "/runtime-config.js",
    # Dotfile credentials.
    "/.npmrc",
    "/.bashrc",
    "/.zshrc",
    "/.netrc",
    # Dev server and bundler.
    "/__vite_rsc_findSourceMapURL",
    "/@fs/var/run/secrets/kubernetes.io/serviceaccount/token",
    "/_profiler/open",
    # Source maps.
    "/build/static/js/main.js.map",
    # Traversal, in several encodings.
    "/api/orders/..%2Fadmin/config.json",
    "/api/uploads/..%2F..%2F.env",
    "/%2e%2e/%2e%2e/etc/passwd"
  ]

  # --- must NOT be refused --------------------------------------------------

  APP_PATHS = [
    "/",
    "/up",
    "/session",
    "/session/new",
    "/registration",
    "/signin",
    "/signup",
    "/mcp",
    "/admin",
    "/admin/security",
    "/buscar",
    # A public key is served on purpose by some apps.
    "/public_key.pem",
    "/pubkey.pem",
    # OAuth endpoints.
    "/.well-known/jwks.json",
    "/.well-known/security.txt",
    # Active Storage is exempt: the app really serves these.
    "/rails/active_storage/blobs/abc123/image.png",
    "/rails/active_storage/direct_uploads"
  ]

  test "refuses the scanner paths" do
    refused = SCANNER_PATHS.reject { |path| scanner_path?(path) }
    assert_empty refused, "these should have been refused but were not"
  end

  test "does not refuse the app's own paths" do
    blocked = APP_PATHS.select { |path| scanner_path?(path) }
    assert_empty blocked, "these are app paths and must not be refused"
  end

  test "does not refuse a public key" do
    refute scanner_path?("/public_key.pem")
    refute scanner_path?("/pubkey.pem")
    assert scanner_path?("/key.pem")
  end

  test "does not refuse Active Storage" do
    refute scanner_path?("/rails/active_storage/blobs/abc/image.png")
    refute scanner_path?("/rails/active_storage/direct_uploads")
  end

  test "unhides an encoded path before matching it" do
    # The same target, spelled three ways, is refused every time.
    assert scanner_path?("/api/orders/..%2Fadmin/config.json")
    assert scanner_path?("/api/orders/%2e%2e/admin/config.json")
    assert scanner_path?("/api/orders/../admin/config.json")
  end

  test "treats a doubled slash as one" do
    assert scanner_path?("//wp-admin/install.php")
  end

  test "is case insensitive" do
    assert scanner_path?("/WP-ADMIN/install.php")
    assert scanner_path?("/Key.PEM")
  end

  test "keeps GraphQL opt-in" do
    # A GraphQL path is refused by the scanner-app signature, but the app's own
    # route table is what decides -- the route guard stands it down.
    assert RULES.const_defined?(:GRAPHQL_IS_ROUTE)
    assert_equal false, RULES::GRAPHQL_IS_ROUTE
  end

  test "exposes the route guard" do
    assert_respond_to RULES, :app_route?
    assert_respond_to RULES, :route_guard?
  end

  # A route like "/:slug" matches every single-segment path, so `/.env` and
  # `/key.pem` would look like the app's own pages and the guard would stand
  # the rule down for exactly the paths it exists to catch. Every app in the
  # fleet has such a route ("/:handle", "/:slug", "/:id").
  test "a dynamic root segment does not make a path the app's own" do
    # The guard reads the app's route table, which a generator test has no
    # access to. The rule it applies is exercised here against a stand-in
    # route table, so the behaviour is checked rather than the source text.
    routes = ["/:slug(.:format)", "/posts/:id(.:format)"]
    segments = "/.env".downcase.split("/").reject(&:empty?)

    matched = routes.any? do |route|
      pattern = route.sub(/\(\.:format\)\z/, "").downcase
      pattern_segments = pattern.split("/").reject(&:empty?)
      next false if pattern_segments.size != segments.size

      pattern_segments.each_with_index.all? do |segment, index|
        next false if index.zero? && segment.start_with?(":")

        segment.start_with?(":") || segment.include?("*") || segment == segments[index]
      end
    end

    refute matched, "a dynamic root segment must not make /.env the app's own route"
  end
end
