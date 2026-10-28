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

    # Airbrake's Rack middleware catches the unhandled request error the Executor
    # also reports, and its ActiveJob rescue_from(Exception) notifies the unhandled job
    # error that the reloader wrap (application.active_support) also reports.
    %w[application.action_dispatch application.active_support].each do |source|
      it "skips the unhandled #{source} report (Airbrake already has it)" do
        expect(Airbrake).not_to receive(:notify)
        Rails.error.report(error, handled: false, source: source)
      end
    end

    # retry_on/discard_on (report: true) rescue the error before Airbrake's
    # job-level handler runs, so nothing else reports it.
    it "forwards application.active_job reports (retry_on/discard_on with report: true)" do
      expect(Airbrake).to receive(:notify).with(error, hash_including(handled: true, rails_source: "application.active_job"))
      Rails.error.report(error, handled: true, source: "application.active_job")
    end

    it "forwards unhandled errors from other sources" do
      expect(Airbrake).to receive(:notify).with(error, hash_including(handled: false))
      Rails.error.report(error, handled: false, source: "application.some_thread")
    end

    it "keeps the caller's context[:source] and puts the Rails source under :rails_source" do
      expect(Airbrake).to receive(:notify).with(error, hash_including(source: "api_v1", rails_source: "application.x"))
      Rails.error.report(error, handled: true, source: "application.x", context: { source: "api_v1" })
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
