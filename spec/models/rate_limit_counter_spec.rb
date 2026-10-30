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
end
