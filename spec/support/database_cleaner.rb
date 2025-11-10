# spec/support/database_cleaner.rb

RSpec.configure do |config|
  config.before(:suite) do
    # First, clean everything
    DatabaseCleaner.clean_with :truncation, except: %w[ar_internal_metadata]
    
    # Then load reference data
    load_order_statuses
    
    # Finally, reset sequences
    reset_all_sequences
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  # Handle system/feature tests
  config.before(:each, type: :system) do
    DatabaseCleaner.strategy = :truncation, { except: %w[ar_internal_metadata order_statuses] }
  end

  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation, { except: %w[ar_internal_metadata order_statuses] }
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end

  # Reset sequences after truncation strategies
  config.after(:each, type: :system) do
    reset_all_sequences
  end

  config.after(:each, js: true) do
    reset_all_sequences
  end
end

# Load reference data (order statuses that should persist)
def load_order_statuses
  OrderStatus.find_or_create_by!(name: "In progress")
  OrderStatus.find_or_create_by!(name: "Completed")
end

# Helper to reset PostgreSQL sequences
def reset_all_sequences
  ActiveRecord::Base.connection.tables.each do |table|
    # Skip Rails internal tables and reference tables
    next if %w[ar_internal_metadata schema_migrations order_statuses].include?(table)
    
    begin
      ActiveRecord::Base.connection.reset_pk_sequence!(table)
    rescue StandardError => e
      # Some tables might not have sequences (join tables, etc.)
      Rails.logger.debug "Could not reset sequence for #{table}: #{e.message}" if defined?(Rails)
    end
  end
end