$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "rails/version"
require "rails/generators"
require "rails/generators/testing/setup_and_teardown"
require "rails/generators/testing/assertions"
