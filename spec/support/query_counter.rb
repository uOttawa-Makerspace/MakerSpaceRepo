# frozen_string_literal: true

# Counts the SQL statements a block runs (cached hits, schema lookups and transaction
# bookkeeping excluded), so a spec can assert that a page's query count does not grow with its rows.
module QueryCounter
  IGNORED_NAMES = %w[SCHEMA TRANSACTION].freeze

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless IGNORED_NAMES.include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end

RSpec.configure { |config| config.include QueryCounter }
