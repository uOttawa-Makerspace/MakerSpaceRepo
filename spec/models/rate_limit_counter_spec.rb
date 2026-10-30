# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateLimitCounter do
  include ActiveSupport::Testing::TimeHelpers

  it "counts up within the window and returns the new count" do
    expect(described_class.increment("k", 1, expires_in: 15.minutes)).to eq(1)
    expect(described_class.increment("k", 1, expires_in: 15.minutes)).to eq(2)
    expect(described_class.increment("k", 3, expires_in: 15.minutes)).to eq(5)
  end

  it "keeps the window's end fixed (it does not slide with each attempt)" do
    freeze_time do
      described_class.increment("k", 1, expires_in: 15.minutes)
      travel 10.minutes
      described_class.increment("k", 1, expires_in: 15.minutes)
      expect(described_class.find("k").expires_at).to eq(5.minutes.from_now)
    end
  end

  it "restarts an expired window in place" do
    described_class.increment("k", 1, expires_in: 15.minutes)
    described_class.increment("k", 1, expires_in: 15.minutes)
    travel 16.minutes do
      expect(described_class.increment("k", 1, expires_in: 15.minutes)).to eq(1)
      expect(described_class.count).to eq(1)
    end
  end

  it "keeps keys apart" do
    described_class.increment("a", 1, expires_in: 1.minute)
    expect(described_class.increment("b", 1, expires_in: 1.minute)).to eq(1)
  end

  it "infers its primary key from the schema (find, delete and the upsert all go by key)" do
    expect(described_class.primary_key).to eq("key")
    described_class.increment("k", 1, expires_in: 1.minute)
    expect(described_class.find("k").count).to eq(1)
    described_class.delete("k")
    expect(described_class.exists?("k")).to be(false)
  end

  it "reset forgets a key" do
    described_class.increment("k", 1, expires_in: 1.minute)
    described_class.reset("k")
    expect(described_class.increment("k", 1, expires_in: 1.minute)).to eq(1)
  end

  describe ".increment_revoking" do
    let!(:user) { create(:user, :regular_user) }

    def call(version = user.token_version)
      described_class.increment_revoking("k", user_id: user.id, token_version: version, max: 2, expires_in: 1.hour)
    end

    it "counts like increment and bumps only on the attempt over max, once" do
      v = user.token_version
      expect(call).to eq([1, nil])
      expect(call).to eq([2, nil])
      expect(call(v)).to eq([3, v + 1])
      expect(call(v)).to eq([4, nil]) # the compare-and-set matches nothing now
      expect(user.reload.token_version).to eq(v + 1)
    end

    it "restarts an expired window like increment" do
      2.times { call }
      travel 2.hours do
        expect(call).to eq([1, nil])
      end
    end

    it "does nothing for a user that does not exist" do
      expect(described_class.increment_revoking("z", user_id: 0, token_version: 0, max: 0, expires_in: 1.hour)).to eq([1, nil])
    end
  end

  describe ".prune!" do
    it "deletes only rows whose window has ended, in batches" do
      stub_const("RateLimitCounter::PRUNE_BATCH", 2)
      5.times { |i| described_class.increment("old-#{i}", 1, expires_in: 1.minute) }
      described_class.increment("live", 1, expires_in: 1.hour)
      travel 2.minutes do
        expect(described_class.prune!).to eq(5)
      end
      expect(described_class.pluck(:key)).to eq(["live"])
    end
  end

  it "is scheduled to be pruned" do
    entry = YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true)
    %w[production staging].each do |env|
      expect(entry.dig(env, "prune_rate_limit_counters", "command")).to eq("RateLimitCounter.prune!")
    end
  end
end
