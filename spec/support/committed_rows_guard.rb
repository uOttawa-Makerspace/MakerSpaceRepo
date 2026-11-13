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
# checked out of the pool for the purpose, never the example's connection: a request returns that
# connection to the pool and a thread of the example may have taken it since. By then the example's
# threads have finished and its transactions have ended, so the plain COUNT cannot wait on a row
# lock the example holds; a lock timeout turns an unexpected wait into a failure instead of a hang.
# The example's own lock waits (its `after` cleanup included) are bounded by the lock_timeout every
# test connection starts with (config/database.yml), so the guard sets nothing on them.
#
# The guard also fails an example that leaves a pooled connection leased to a thread other than its
# own, finished or still running: a thread that ends holding its lease keeps the connection out of
# the pool until the pool's reaper takes it back and resets it, at a moment no example controls.
# Threads started with `in_thread` or `race_thread` (spec/support/race_thread.rb) and joined before
# the example ends always give their connection back.
module CommittedRowsGuard
  IGNORED_TABLES = %w[schema_migrations ar_internal_metadata].freeze
  # Rows the suite itself seeds (rails_helper's before(:suite)) and keeps between runs.
  SEEDED_TABLES = %w[order_statuses].freeze

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
        conn.execute("SET LOCAL max_parallel_workers_per_gather = 0")
        conn.select_rows(sql).to_h { |t, n| [t, n.to_i] }
      end
    ensure
      pool.checkin(conn)
    end
  end

  # Worker test databases persist between runs. A row left by an earlier run is invisible to the
  # before/after comparison, so the suite refuses to start on a database that is not empty.
  def self.stale_rows(counts = self.counts)
    counts.reject { |table, n| n.zero? || SEEDED_TABLES.include?(table) }
  end

  def self.stale_rows_message(stale)
    listed = stale.map { |table, n| "#{table} (#{n})" }.join(", ")
    "The test database already holds rows from an earlier run: #{listed}. Recreate the worker test databases."
  end

  def self.leaked_message(leaked)
    message = leaked.map { |table, delta| "#{table} (#{delta.positive? ? '+' : ''}#{delta})" }.join(", ")
    "This non-transactional example changed committed rows and did not undo it: #{message}"
  end

  def self.connections_held_by_other_threads
    me = ActiveSupport::IsolatedExecutionState.context
    ActiveRecord::Base.connection_handler.connection_pool_list(:all).flat_map(&:connections).select do |conn|
      conn.owner && !conn.owner.equal?(me)
    end
  end

  def self.held_connections_message(held)
    owners = held.map { |conn| conn.owner.alive? ? "a running thread" : "a finished thread" }
    "This example left #{held.size} pooled connection(s) leased to #{owners.uniq.join(' and ')}. " \
      "Start its threads with in_thread or race_thread and join them before the example ends."
  end

  def self.leaked(before, after)
    (before.keys & after.keys).filter_map { |t| [t, after[t] - before[t]] if after[t] != before[t] }
  end
end

RSpec.configure do |config|
  config.before(:suite) do
    stale = CommittedRowsGuard.stale_rows
    abort(CommittedRowsGuard.stale_rows_message(stale)) unless stale.empty?
  end

  config.around(:each) do |example|
    non_transactional = respond_to?(:use_transactional_tests) && !use_transactional_tests
    unless non_transactional
      example.run
      next
    end

    before = CommittedRowsGuard.counts
    example.run

    # Checked even when the example failed: its own error stays and the leftovers are added to it.
    held = CommittedRowsGuard.connections_held_by_other_threads
    leaked = CommittedRowsGuard.leaked(before, CommittedRowsGuard.counts)
    problems = []
    problems << CommittedRowsGuard.leaked_message(leaked) unless leaked.empty?
    problems << CommittedRowsGuard.held_connections_message(held) unless held.empty?
    raise problems.join("\n") unless problems.empty?
  end
end
