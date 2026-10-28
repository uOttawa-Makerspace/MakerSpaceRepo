# frozen_string_literal: true

require "rails_helper"

RSpec.describe AirbrakeErrorSubscriber do
  let(:error) { RuntimeError.new("boom") }

  it "is registered with Rails.error" do
    subscribers = Rails.error.instance_variable_get(:@subscribers)
    expect(subscribers.map(&:class)).to include(described_class)
  end

  context "when Airbrake is configured" do
    before { allow(Airbrake).to receive(:configured?).and_return(true) }

    it "turns Rails.error.report into an Airbrake.notify with the context" do
      expect(Airbrake).to receive(:notify).with(error, hash_including(blob_id: 5, handled: true, severity: :warning))
      Rails.error.report(error, handled: true, severity: :warning, context: { blob_id: 5 })
    end

    it "does not send unhandled errors the Rack/ActiveJob integrations already catch" do
      expect(Airbrake).not_to receive(:notify)
      Rails.error.report(error, handled: false, source: "application.action_dispatch")
    end

    it "never raises into the caller" do
      allow(Airbrake).to receive(:notify).and_raise(Timeout::Error)
      expect { Rails.error.report(error, handled: true) }.not_to raise_error
    end
  end

  it "does nothing when Airbrake is not configured" do
    allow(Airbrake).to receive(:configured?).and_return(false)
    expect(Airbrake).not_to receive(:notify)
    Rails.error.report(error, handled: true)
  end
end
