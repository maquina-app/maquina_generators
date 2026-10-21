$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "active_support/test_case"
require "rails/version"
require "rails/generators"
require "rails/generators/testing/setup_and_teardown"
require "rails/generators/testing/assertions"
