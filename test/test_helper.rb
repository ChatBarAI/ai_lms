ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "securerandom"

# Initializers (terminology, Sidekiq and Rack::Attack) inspect SiteSetting before
# rails/test_help prepares the test schema. Discard model metadata loaded against
# the old schema before it is inherited by the parallel test workers.
ActiveRecord::Base.descendants.each(&:reset_column_information)

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
