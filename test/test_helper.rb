ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "securerandom"

module PasswordTestHelper
  def generated_password
    SecureRandom.alphanumeric(24)
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    include PasswordTestHelper
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PasswordTestHelper
end
