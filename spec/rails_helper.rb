# frozen_string_literal: true

require "spec_helper"
require "factory_bot"
require "support/factory_bot"
require "rspec/json_expectations"

# Coverage is opt-in (COVERAGE=1): instrumenting every line slows the suite.
# CI and stage gates set it. Under parallel_tests each worker writes its own
# coverage/<n>/ directory; bin/parallel_rspec (and CI) merge them afterwards
# with bin/coverage_collate.
unless ENV["COVERAGE"].to_s.empty?
  require "simplecov"
  if ENV["TEST_ENV_NUMBER"]
    worker = ENV["TEST_ENV_NUMBER"].to_s.empty? ? "1" : ENV["TEST_ENV_NUMBER"]
    SimpleCov.command_name "rspec-#{worker}"
    SimpleCov.coverage_dir "coverage/#{worker}"
    # the merged HTML report is produced once by bin/coverage_collate
    SimpleCov.formatter Class.new { def format(_result) = nil }
  end
  SimpleCov.start
end

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
  # The :test queue adapter keeps enqueued/performed jobs for the whole process.
  # Start every example with empty queues, otherwise `not_to have_been_enqueued`
  # depends on which example ran before it (random order, parallel workers).
  config.before(:each) do
    ([ActiveJob::Base] + ActiveJob::Base.descendants).each do |job_class|
      adapter = job_class.queue_adapter
      next unless adapter.respond_to?(:enqueued_jobs)

      adapter.enqueued_jobs.clear
      adapter.performed_jobs.clear
    end
  end

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
