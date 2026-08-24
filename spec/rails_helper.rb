# frozen_string_literal: true

require "spec_helper"
require "factory_bot"
require "support/factory_bot"
require "simplecov"
require "rspec/json_expectations"

SimpleCov.start

ENV["RAILS_ENV"] = "test"
require File.expand_path("../config/environment", __dir__)

if Rails.env.production?
  abort("The Rails environment is running in production mode!")
end
require "rspec/rails"

Dir[Rails.root.join("spec", "support", "**", "*.rb")].sort.each do |f|
  require f
end

BCrypt::Engine.cost = BCrypt::Engine::MIN_COST

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

RSpec.configure do |config|
  include ActiveJob::TestHelper
  
  # [SPEED] Use native transactions (standard for Rails 5.1+)
  config.use_transactional_fixtures = true
  config.render_views

  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.before(:suite) do
    # Load any essential seed reference data
    OrderStatus.find_or_create_by!(name: "In progress")
    OrderStatus.find_or_create_by!(name: "Completed")
  end

  # [SPEED] Mock Google Calendar Sync for Events
  config.before(:each) do
    allow(Event).to receive(:upsert_event).and_return(true)
    allow(Event).to receive(:delete_event).and_return(true)
    allow(Event).to receive(:authorizer).and_return(double("GoogleAuthorizer", fetch_access_token!: true))
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
