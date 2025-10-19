RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.clean_with :truncation, except: %w[ar_internal_metadata]
  end

  config.before(:each) { DatabaseCleaner.strategy = :transaction }

  config.before(:each) { DatabaseCleaner.start }

  config.after(:each) { DatabaseCleaner.clean }
end
