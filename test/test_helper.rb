ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Each parallel worker writes its own data plane directory
    parallelize_setup do |worker|
      Rails.application.config.x.data_plane_root = Rails.root.join("tmp/test_data_plane", worker.to_s)
    end

    setup { FileUtils.rm_rf(DataPlane.root) }
  end
end
