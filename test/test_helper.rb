# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require "simplecov"
SimpleCov.start
require File.expand_path("../config/environment", __dir__)
require "rails/test_help"
require "mocha/test_unit"

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
end
