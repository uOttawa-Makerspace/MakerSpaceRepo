# frozen_string_literal: true

require "rails_helper"

# Production and staging use Solid Cache as Rails.cache, so every rate_limit (and
# the re-authentication counter) counts through Store#increment. Real separate
# database connections (one per thread), no transaction wrapping the example:
# every increment must be counted, none lost, as with Puma workers in separate
# processes. The test environment's default store is a null store; this spec
# builds the real Solid Cache store against the same table.
RSpec.describe "Solid Cache counters across connections", type: :model do
  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false

  let(:store) { SolidCache::Store.new(namespace: "counter-spec") }
  let(:key) { "counter-spec:#{SecureRandom.hex(6)}" }

  after { SolidCache::Entry.delete_all }

  it "counts increments from separate connections without losing any" do
    store.increment(key, 1, expires_in: 5.minutes) # the first write of a key is not contended
    threads = Array.new(8) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Array.new(10) { store.increment(key, 1, expires_in: 5.minutes) }
        end
      end
    end
    returned = threads.flat_map(&:value)

    expect(returned.sort).to eq((2..81).to_a) # each caller saw its own, distinct count
    expect(store.read(key, raw: true).to_i).to eq(81)
  end

  it "starts a new window once the old one has expired" do
    store.increment(key, 1, expires_in: 1.minute)
    travel_to(2.minutes.from_now) do
      expect(store.increment(key, 1, expires_in: 1.minute)).to eq(1)
    end
  end
end
