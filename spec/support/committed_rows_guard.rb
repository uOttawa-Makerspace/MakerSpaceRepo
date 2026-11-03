# frozen_string_literal: true

# A non-transactional example (real second connections, so its rows are COMMITTED) must delete
# every row it created, in every table. A row left behind is invisible to that example and turns
# up much later in whichever unrelated example the random order runs next: a stray user whose
# Faker name contains a search term, an extra committed row that changes a `count`, a uniqueness
# check or the first record a controller picks. It only fails for the seeds that put the two
# together, so the example that leaks is the one to fail.
#
# The guard compares per-table row counts taken before the example and after it, over every
# application table. It is an `around` hook so the second count runs once the example's own
# `after` hooks (and any cleanup hook in spec/support) are done, and it counts on a connection
# checked out of the pool for the purpose, never the example's connection. By then the example's
# threads have finished and its transactions have ended, so the plain COUNT cannot wait on a row
# lock the example holds; a lock timeout turns an unexpected wait into a failure instead of a hang.
module CommittedRowsGuard
  IGNORED_TABLES = %w[schema_migrations ar_internal_metadata].freeze

  # One UNION ALL query inside a transaction, so the lock timeout (SET LOCAL) ends with it and
  # cannot outlive the count on a connection that goes back to the pool.
  def self.counts
    pool = ActiveRecord::Base.connection_pool
    conn = pool.checkout
    begin
      tables = (conn.tables - IGNORED_TABLES).sort
      return {} if tables.empty?

      sql = tables.map { |t| "SELECT #{conn.quote(t)} AS t, count(*) AS n FROM #{conn.quote_table_name(t)}" }.join(" UNION ALL ")
      conn.transaction do
        conn.execute("SET LOCAL lock_timeout = '10s'")
        conn.select_rows(sql).to_h { |t, n| [t, n.to_i] }
      end
    ensure
      pool.checkin(conn)
    end
  end

  def self.leaked(before, after)
    (before.keys & after.keys).filter_map { |t| [t, after[t] - before[t]] if after[t] != before[t] }
  end
end

RSpec.configure do |config|
  config.around(:each) do |example|
    non_transactional = respond_to?(:use_transactional_tests) && !use_transactional_tests
    before = CommittedRowsGuard.counts if non_transactional
    example.run
    next unless non_transactional && example.exception.nil?

    leaked = CommittedRowsGuard.leaked(before, CommittedRowsGuard.counts)
    next if leaked.empty?

    message = leaked.map { |table, delta| "#{table} (#{delta.positive? ? '+' : ''}#{delta})" }.join(", ")
    raise "This non-transactional example changed committed rows and did not undo it: #{message}"
  end
end
