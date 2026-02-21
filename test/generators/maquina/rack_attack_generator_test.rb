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

  test "blocks PHP file requests" do
    run_generator

    assert_file "config/initializers/rack_attack.rb", /block-php/
    assert_file "config/initializers/rack_attack.rb", /\.php/
  end

  test "blocks WordPress paths" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/block-wordpress/, content)
      assert_match(%r{/wp-admin}, content)
      assert_match(%r{/wp-login}, content)
      assert_match(%r{/wp-content}, content)
      assert_match(%r{/xmlrpc\.php}, content)
    end
  end

  test "blocks sensitive file access" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/block-sensitive-files/, content)
      assert_match(%r{/\.env}, content)
      assert_match(%r{/\.git}, content)
      assert_match(%r{/\.htaccess}, content)
      assert_match(%r{/etc/passwd}, content)
    end
  end

  test "blocks scanner targets" do
    run_generator

    assert_file "config/initializers/rack_attack.rb" do |content|
      assert_match(/block-scanner-targets/, content)
      assert_match(%r{/phpmyadmin}, content)
      assert_match(%r{/cgi-bin}, content)
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
      assert_match(/limit: 300/, content)
      assert_match(/login\/ip/, content)
      assert_match(/limit: 5/, content)
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
