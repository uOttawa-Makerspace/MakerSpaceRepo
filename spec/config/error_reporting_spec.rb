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

    it "puts the request id and reference of the context on the notice context" do
      notice = Struct.new(:context).new({}).tap { |n| n.define_singleton_method(:[]) { |_k| context } }
      allow(Airbrake).to receive(:notify).with(error, anything).and_yield(notice)
      Rails.error.report(error, handled: true, context: { request_id: "abc-123", reference: "abc", other: 1 })
      expect(notice.context).to eq(request_id: "abc-123", reference: "abc")
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

RSpec.describe AirbrakeRequestReferenceFilter do
  let(:notice) { Struct.new(:stash, :context).new(stash, {}).tap { |n| n.define_singleton_method(:[]) { |k| context if k == :context } } }

  context "with a request" do
    let(:stash) { { rack_request: double("request", request_id: "3f2a9c1e-7b64") } }

    it "puts the request id and reference on the notice context" do
      described_class.new.call(notice)
      expect(notice.context).to eq(request_id: "3f2a9c1e-7b64", reference: "3f2a9c1e")
    end
  end

  context "without a request" do
    let(:stash) { {} }

    it "leaves the context alone" do
      described_class.new.call(notice)
      expect(notice.context).to eq({})
    end
  end
end
