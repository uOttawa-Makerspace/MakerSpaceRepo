# frozen_string_literal: true

# A concurrency spec runs each competing side on its own thread with its own pooled connection (a
# separate database session, so row locks really compete). Start those threads with these helpers.
# The block gets a connection from the pool, and the pool takes it back when the block ends, even
# when code inside asked for `ActiveRecord::Base.connection`, which on its own keeps the connection
# leased to the thread after the thread has finished. Join every thread (`value` or `join`) before
# the example ends: the committed rows guard fails an example that leaves a pooled connection
# leased to any thread but the example's own.
module RaceThread
  def self.with_own_connection(&)
    ActiveRecord::Base.connection_pool.with_connection(prevent_permanent_checkout: true, &)
  end

  # The thread's value is the block's result; an error raised in the block is raised again by
  # `value` (and `join`).
  def race_thread(&block)
    Thread.new { RaceThread.with_own_connection(&block) }
  end

  # The thread's value is the block's result, or the StandardError the block raised, for races
  # where one side is expected to lose with an error.
  def in_thread(&block)
    Thread.new do
      RaceThread.with_own_connection(&block)
    rescue StandardError => e
      e
    end
  end
end

RSpec.configure do |config|
  config.include RaceThread
end
