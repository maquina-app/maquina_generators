require "test_helper"
require "generators/maquina/rack_attack/rack_attack_generator"
require "erb"
# The template uses ActiveSupport's duration helpers (7.days, 10.minutes).
require "active_support/core_ext/integer/time"
# The route guard asks Mime which formats Rails knows.
require "action_dispatch"
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

  # What maquina:oauth and maquina:mcp serve. An AI client that tripped the
  # scanner ban here would be locked out of the app for a week.
  OAUTH_PATHS = [
    "/mcp",
    "/oauth/authorize",
    "/oauth/token",
    "/oauth/revoke",
    "/.well-known/oauth-authorization-server",
    "/.well-known/oauth-protected-resource/mcp",
    "/settings/connected_apps",
    "/settings/connected_apps/1"
  ]

  test "does not refuse the OAuth and MCP endpoints" do
    blocked = OAUTH_PATHS.select { |path| scanner_path?(path) }
    assert_empty blocked, "maquina:oauth and maquina:mcp serve these"
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

  # --- the route guard ------------------------------------------------------

  ROUTES = [
    "/session(.:format)",
    "/service-worker(.:format)",
    "/api-docs(.:format)",
    "/posts/:id(.:format)",
    "/app/errors/*path(.:format)",
    "/skills/mcp/SKILL.md(.:format)"
  ].freeze

  def app_route?(path, routes: ROUTES)
    RULES.app_route?(path, routes:)
  end

  test "the guard owns a route the app serves" do
    assert app_route?("/api-docs")
    assert app_route?("/posts/1")
    assert app_route?("/app/errors/a")
    refute app_route?("/.env")
    refute app_route?("/wp-login.php")
  end

  test "a format Rails knows counts as the route" do
    assert app_route?("/service-worker.js")
    assert app_route?("/api-docs.json")
    assert app_route?("/skills/mcp/SKILL.md")
  end

  # These are the guesses a scanner makes, and /session is a real route.
  test "a format Rails doesn't know does not" do
    refute app_route?("/session.php")
    refute app_route?("/session.env")
    refute app_route?("/session.pem")
  end

  # Registered on every page of a PWA, and it matches CONFIG_DUMP_PATHS: without
  # the guard, three page loads ban the visitor for a week.
  test "the service worker is a scanner path that the guard stands down" do
    assert scanner_path?("/service-worker.js")
    assert app_route?("/service-worker.js")
  end

  test "a dynamic root segment does not make a path the app's own" do
    routes = ["/:slug(.:format)", "/posts/:id(.:format)"]

    refute app_route?("/.env", routes:)
    refute app_route?("/key.pem", routes:)
    assert app_route?("/posts/1", routes:)
  end

  # A catch-all used to switch the guard off for the whole app.
  test "a root catch-all does not own a path, and the other routes stay protected" do
    routes = [*ROUTES, "/*path(.:format)"]

    refute app_route?("/.env", routes:)
    refute app_route?("/secrets.json", routes:)
    refute app_route?("/a/b", routes:)
    assert app_route?("/api-docs", routes:)
    assert app_route?("/service-worker.js", routes:)
  end

  test "an unreadable route table leaves the decision to the patterns" do
    refute RULES.app_route?("/api-docs", routes: Object.new)
  end
end
