# frozen_string_literal: true

# A migration spec that drops a column and adds it back leaves the column last in the table, so the row
# type of `SELECT table.*` changes. A plan another pooled connection prepared for that query before the
# change is then refused inside a transaction (PreparedStatementCacheExpired, "cached plan must not change
# result type"), in whichever later example reuses that connection. Rails forgets the prepared statements
# of the connection that ran add_column, but not those of the pool's other connections. A migration spec
# that adds or removes columns outside a transaction calls this after each migration it runs.
#
# Only connections the current thread holds are cleared directly. The pool's other connections may be in
# use by another thread at that moment (the pool's background reaper pings, retires and flushes idle
# connections; a system spec's server thread runs queries), and an adapter is not safe to use from two
# threads, so clearing their statements could race with that thread's I/O. Instead the pool disconnects
# its idle connections under its own lock (`flush!`), and the next checkout opens a fresh session with no
# prepared statements. A connection another thread holds is left alone.
module PooledStatements
  def self.reset
    me = ActiveSupport::IsolatedExecutionState.context
    ActiveRecord::Base.connection_handler.connection_pool_list(:all).each do |pool|
      pool.connections.select { |conn| conn.owner == me }.each(&:clear_cache!)
      pool.flush!
    end
  end
end
