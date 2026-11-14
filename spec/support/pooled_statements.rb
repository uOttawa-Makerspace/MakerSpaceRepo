# frozen_string_literal: true

# A migration spec that drops a column and adds it back leaves the column last in the table, so the row
# type of `SELECT table.*` changes. A plan another pooled connection prepared for that query before the
# change is then refused inside a transaction (PreparedStatementCacheExpired, "cached plan must not change
# result type"), in whichever later example reuses that connection. Rails forgets the prepared statements
# of the connection that ran add_column, but not those of the pool's other connections. A migration spec
# that adds or removes columns outside a transaction calls this after each migration it runs.
module PooledStatements
  def self.reset
    ActiveRecord::Base.connection_handler.connection_pool_list(:all).flat_map(&:connections).each(&:clear_cache!)
  end
end
