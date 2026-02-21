# This file is copied to spec/ when you run 'rails generate rspec:install'

require "spec_helper"
require "factory_bot"
require "support/factory_bot"
# require "support/database_cleaner" # <--- Disabled: Use native transactions for speed
require "simplecov"
require "rspec/json_expectations"

# [SPEED] Enable let_it_be for fast object creation
require "test_prof/recipes/rspec/let_it_be"

SimpleCov.start

ENV["RAILS_ENV"] ||= "test"
require File.expand_path("../config/environment", __dir__)
# Prevent database truncation if the environment is production
if Rails.env.production?
  abort("The Rails environment is running in production mode!")
end
require "rspec/rails"

Dir[Rails.root.join("spec", "support", "**", "*.rb")].sort.each do |f|
  require f
end

# Fastest encryption when testing
BCrypt::Engine.cost = BCrypt::Engine::MIN_COST

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

RSpec.configure do |config|
  include ActiveJob::TestHelper
  
  # [SPEED] Use transactions. 
  # This is much faster than DatabaseCleaner truncation strategies.
  config.use_transactional_fixtures = true
  config.render_views

  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # [SPEED] Mock Google Calendar Sync for Events
  config.before(:each) do
    # Stub the class methods on Event to do nothing
    allow(Event).to receive(:upsert_event).and_return(true)
    allow(Event).to receive(:delete_event).and_return(true)
    
    # Also stub authorizer just in case something calls it directly
    allow(Event).to receive(:authorizer).and_return(double("GoogleAuthorizer", fetch_access_token!: true))
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
