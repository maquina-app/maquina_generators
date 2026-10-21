require "test_helper"
require "generators/maquina/rack_attack/rack_attack_generator"

class Maquina::Generators::RackAttackGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::RackAttackGenerator
  destination File.expand_path("../../tmp", __dir__)

  setup do
    prepare_destination

    mkdir_p("config")
    File.write(
      File.join(destination_root, "config/routes.rb"),
      "Rails.application.routes.draw do\nend\n"
    )

    File.write(
      File.join(destination_root, "Gemfile"),
      "source \"https://rubygems.org\"\n"
    )
  end

  test "generates initializer" do
    run_generator

    assert_file "config/initializers/rack_attack.rb"
  end

  test "bans scanners with fail2ban" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(%r{fail2ban/scanners}, content)
      assert_match(/SCANNER_MAXRETRY = 3/, content)
      assert_match(/SCANNER_BANTIME = 7\.days/, content)
      assert_match(/def self\.scanner_path\?/, content)
      assert_match(/def self\.banned\?/, content)
    end
  end

  test "treats PHP, WordPress, sensitive files and archives as scanner paths" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/PHP_PATH/, content)
      assert_match(/ARCHIVE_PATH/, content)
      assert_match(%r{/wp-admin}, content)
      assert_match(%r{/xmlrpc\.php}, content)
      assert_match(%r{/\.env}, content)
      assert_match(%r{/\.git}, content)
      assert_match(%r{/etc/passwd}, content)
      assert_match(%r{/phpmyadmin}, content)
      assert_match(%r{/cgi-bin}, content)
    end
  end

  test "treats cloud keys, container runtime, dev-server and infra files as scanner paths" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/CLOUD_KEY_PATHS/, content)
      assert_match(/CONTAINER_PATHS/, content)
      assert_match(/IAC_PATHS/, content)
      assert_match(/SECRET_FILE_PATHS/, content)
      assert_match(/CONFIG_DUMP_PATHS/, content)
      assert_match(/DOTFILE_CRED_PATHS/, content)
      assert_match(/DEV_SERVER_PATHS/, content)
      assert_match(/SOURCE_MAP_PATHS/, content)
      assert_match(/TRAVERSAL_PATHS/, content)
      assert_match(/PRIVATE_KEY_PATHS/, content)
      # The containers the rules name.
      assert_match(%r{/var/run/secrets}, content)
      assert_match(%r{service[_-]?account}, content)
      assert_match(%r{docker-compose}, content)
      assert_match(%r{terraform\.tfstate}, content)
      assert_match(%r{__vite_rsc_}, content)
    end
  end

  test "unhides an encoded path before matching it" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/ENCODED_DOTS/, content)
      assert_match(/ENCODED_SLASHES/, content)
      assert_match(/gsub\(ENCODED_DOTS/, content)
    end
  end

  test "exempts a public key from the private-key rule" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/PUBLIC_KEY_EXCEPTIONS/, content)
      assert_match(/!path\.match\?\(PUBLIC_KEY_EXCEPTIONS\)/, content)
    end
  end

  test "stands a rule down when the app routes the path" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/def self\.app_route\?/, content)
      assert_match(/def self\.route_guard\?/, content)
      # The blocklist asks the guard before refusing.
      assert_match(/Rack::Attack\.scanner_path\?\(req\.path\) && !Rack::Attack\.app_route\?\(req\.path\)/, content)
    end
  end

  test "the route guard stands down when the app has a root catch-all" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/root_catchall/, content)
      assert_match(/first\.include\?\("\*"\)/, content)
    end
  end

  test "keeps GraphQL opt-in" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/GRAPHQL_IS_ROUTE = false/, content)
      assert_match(/GRAPHQL_PATHS/, content)
    end
  end

  test "does not name a real sign-in route as a scanner path" do
    # "/login" is an ordinary route name. The Jenkins signature used to include
    # it, which would have blocked a real sign-in page.
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_no_match(%r{^\s*\|\s*\^/\(script\|view\|job\|build}, content)
    end
  end

  test "exempts Active Storage from scanner paths and the general throttle" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(%r{return false if path\.start_with\?\("/rails/active_storage"\)}, content)
      assert_match(%r{req\.path\.start_with\?\("/assets", "/rails/active_storage"\)}, content)
    end
  end

  test "bans floods with allow2ban" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(%r{allow2ban/flood}, content)
      assert_match(/FLOOD_MAXRETRY = GENERAL_LIMIT \* 2/, content)
      assert_match(/FLOOD_BANTIME = 1\.day/, content)
    end
  end

  test "safelists localhost" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/allow-localhost/, content)
      assert_match(/127\.0\.0\.1/, content)
      assert_match(/::1/, content)
    end
  end

  test "includes throttle rules" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/req\/ip/, content)
      assert_match(/GENERAL_LIMIT = 300/, content)
      assert_match(/login\/ip/, content)
      assert_match(/LOGIN_LIMIT = 5/, content)
      assert_match(%r{LOGIN_PATH = "/session"}, content)
    end
  end

  test "throttles a custom login path" do
    run_generator %w[--login-path /sign_in]

    assert_file "config/initializers/rack_attack.rb", %r{LOGIN_PATH = "/sign_in"}
  end

  test "logs every refusal" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/subscribe\("rack\.attack"\)/, content)
      assert_match(/\[ATTACK\]/, content)
    end
  end

  test "returns 403 for blocklisted requests" do
    run_generator

    assert_file "config/initializers/rack_attack.rb", /blocklisted_responder/
    assert_file "config/initializers/rack_attack.rb", /403/
  end

  test "adds gem to Gemfile" do
    run_generator

    assert_file "Gemfile", /gem "rack-attack"/
  end

  test "does not duplicate gem in Gemfile" do
    File.write(
      File.join(destination_root, "Gemfile"),
      "source \"https://rubygems.org\"\ngem \"rack-attack\"\n"
    )

    run_generator

    assert_file "Gemfile" do |content|
      assert_equal 1, content.scan('gem "rack-attack"').length
    end
  end

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
