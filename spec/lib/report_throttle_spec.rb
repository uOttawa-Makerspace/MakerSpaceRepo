# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/report_throttle")

RSpec.describe ReportThrottle do
  include ActiveSupport::Testing::TimeHelpers

  subject(:throttle) { described_class.new(interval: 10.minutes) }

  it "allows once per kind per interval, then again after it, and resets" do
    travel_to(Time.zone.local(2026, 1, 1)) do
      expect(throttle.allow?(:a)).to be(true)
      expect(throttle.allow?(:a)).to be(false)
      expect(throttle.allow?(:b)).to be(true)
      travel 10.minutes
      expect(throttle.allow?(:a)).to be(true)
      throttle.reset!
      expect(throttle.allow?(:a)).to be(true)
    end
  end
end
