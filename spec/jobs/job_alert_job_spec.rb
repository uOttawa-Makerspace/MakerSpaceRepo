# frozen_string_literal: true

require "rails_helper"

RSpec.describe JobAlertJob do
  it "runs the alert once and logs how many jobs it reported" do
    alert = instance_double(JobAlert, run: 2)
    allow(JobAlert).to receive(:new).and_return(alert)
    allow(Rails.logger).to receive(:info)

    described_class.perform_now

    expect(alert).to have_received(:run).once
    expect(Rails.logger).to have_received(:info).with("[JobAlertJob] Reported 2 jobs")
  end

  it "stays quiet when nothing was reported" do
    allow(JobAlert).to receive(:new).and_return(instance_double(JobAlert, run: 0))
    expect(Rails.logger).not_to receive(:info).with(/JobAlertJob/)

    described_class.perform_now
  end
end
