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
end
