# frozen_string_literal: true

require "rails_helper"

# Every rate_limit counts through RateLimitCounter.increment. Real separate
# database connections (one per thread), no transaction wrapping the example,
# as with Puma workers in separate processes: no increment may be lost, and
# each caller must see its own distinct count, INCLUDING a burst on a key that
# has no row yet (the case Solid Cache's SELECT ... FOR UPDATE cannot serialize).
RSpec.describe RateLimitCounter, "across connections", type: :model do
  self.use_transactional_tests = false

  let(:key) { "counter-spec:#{SecureRandom.hex(6)}" }

  after { described_class.where("key LIKE 'counter-spec:%'").delete_all }

  def burst(threads:, per_thread: 1)
    ready = Queue.new
    go = Queue.new
    workers = Array.new(threads) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          Array.new(per_thread) { yield }
        end
      end
    end
    threads.times { ready.pop }
    threads.times { go << true }
    workers.flat_map(&:value)
  end

  # One burst can pass by luck on a store that cannot serialize a missing row, so
  # many fresh keys are tried: every one must count exactly 1..N.
  it "counts a parallel burst on a fresh key (no row yet) without losing any" do
    30.times do |round|
      fresh = "#{key}:#{round}"
      returned = burst(threads: 8) { described_class.increment(fresh, 1, expires_in: 5.minutes) }

      expect(returned.sort).to eq((1..8).to_a)
      expect(described_class.find(fresh).count).to eq(8)
    end
  end

  it "counts repeated increments from separate connections without losing any" do
    described_class.increment(key, 1, expires_in: 5.minutes)
    returned = burst(threads: 8, per_thread: 10) { described_class.increment(key, 1, expires_in: 5.minutes) }

    expect(returned.sort).to eq((2..81).to_a)
    expect(described_class.find(key).count).to eq(81)
  end

  # prune! picks its candidates in a subquery, then deletes them. A concurrent increment that restarts a candidate's
  # window after that snapshot (here: an open transaction holding the row, committed once prune! is blocked on it)
  # must keep its row: deleting it would hand an attacker a fresh budget mid-window.
  it "prune! does not delete a counter whose window a concurrent increment restarted after the candidates were picked" do
    described_class.increment(key, 4, expires_in: 1.minute)
    described_class.where(key: key).update_all(expires_at: 1.minute.ago)

    holder_ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.transaction do
          conn.execute("UPDATE rate_limit_counters SET count = 1, expires_at = now() + interval '1 hour' WHERE key = #{conn.quote(key)}")
          holder_ready << true
          release.pop
        end
      end
    end
    holder_ready.pop

    pruner = Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.prune! } }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until described_class.connection.select_value("SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND query LIKE 'DELETE FROM \"rate_limit_counters\"%'").to_i.positive?
      raise "prune! never blocked on the row lock" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
    release << true
    holder.join

    expect(pruner.value).to eq(0)
    expect(described_class.find(key).count).to eq(1)
  end
end
