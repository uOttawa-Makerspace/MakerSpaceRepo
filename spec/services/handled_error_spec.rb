# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandledError do
  let(:error) { RuntimeError.new("boom") }

  it "reports the error to Rails.error as handled, with the context and severity" do
    expect(Rails.error).to receive(:report)
      .with(error, handled: true, severity: :warning, context: { source: "x", id: 1 })
    described_class.report(error, severity: :warning, source: "x", id: 1)
  end

  it "defaults to error severity and logs the class and message under the source" do
    allow(Rails.error).to receive(:report)
    expect(Rails.logger).to receive(:error).with("[x] RuntimeError: boom")
    described_class.report(error, source: "x")
    expect(Rails.error).to have_received(:report).with(error, handled: true, severity: :error, context: { source: "x" })
  end

  it "names the log line generically when no source is given" do
    allow(Rails.error).to receive(:report)
    expect(Rails.logger).to receive(:error).with("[handled error] RuntimeError: boom")
    described_class.report(error)
  end
end
