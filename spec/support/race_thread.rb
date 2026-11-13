# frozen_string_literal: true

# A concurrency spec runs each competing side on its own thread with its own pooled connection (a
# separate database session, so row locks really compete). Start those threads with these helpers.
# The block gets a connection from the pool, and the pool takes it back when the block ends, even
# when code inside asked for `ActiveRecord::Base.connection`, which on its own keeps the connection
# leased to the thread after the thread has finished. Join every thread (`value` or `join`) before
# the example ends: the committed rows guard fails an example that leaves a pooled connection
# leased to any thread but the example's own. Whatever the example does, those threads are waited
# for before its `after` hooks run, so a failing example's cleanup cannot race a thread still writing.
module RaceThread
  def self.with_own_connection(&)
    ActiveRecord::Base.connection_pool.with_connection(prevent_permanent_checkout: true, &)
  end

  # The thread's value is the block's result; an error raised in the block is raised again by
  # `value` (and `join`).
  def race_thread(&block)
    start_race_thread { RaceThread.with_own_connection(&block) }
  end

  # The thread's value is the block's result, or the StandardError the block raised, for races
  # where one side is expected to lose with an error.
  def in_thread(&block)
    start_race_thread do
      RaceThread.with_own_connection(&block)
    rescue StandardError => e
      e
    end
  end

  # Waits for every thread started with `race_thread` or `in_thread` in this example to finish. It runs
  # before the example's own `after` hooks, so when the example body fails with a thread still
  # parked or working, the thread's late writes land before the cleanup and not after it.
  # A thread still running when the wait ends fails the example, naming its location.
  def settle_race_threads(timeout = ThreadPause::LOCK_TIMEOUT)
    queues = @race_thread_finished || []
    queues.each { |finished| finished.pop(timeout: timeout) }
    return if queues.all?(&:closed?)

    raise "race thread still running after #{timeout} s (#{RSpec.current_example&.location})"
  end

  private

  # `finished` is closed when the thread ends, whatever the block did.
  def start_race_thread
    finished = Queue.new
    (@race_thread_finished ||= []) << finished
    settle_race_threads_first
    Thread.new do
      yield
    ensure
      finished.close
    end
  end

  # A hook added to the example's group while it runs is the last one declared, so it runs before the
  # group's own `after` hooks. It stays for the group's later examples, where it has nothing to wait for.
  def settle_race_threads_first
    group = self.class
    return if group.instance_variable_defined?(:@settles_race_threads)

    group.instance_variable_set(:@settles_race_threads, true)
    group.after { settle_race_threads }
  end
end

RSpec.configure do |config|
  config.include RaceThread
end
