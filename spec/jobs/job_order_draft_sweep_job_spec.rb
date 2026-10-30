# frozen_string_literal: true

require "rails_helper"

RSpec.describe JobOrderDraftSweepJob, type: :job do

  include ShopSpecHelpers

  let!(:shopify) { stub_shopify_admin! }

  it "runs JobOrder::DraftSweep and is quiet when nothing is unresolved" do
    expect { described_class.perform_now }.not_to raise_error
  end

  it "completes while a draft is unresolved and reports it once (it must not fail every hour for the same draft)" do
    shopify.status = 502
    expect(Rails.error).to receive(:report).once
    expect { described_class.perform_now }.not_to raise_error
  end

  it "is scheduled in config/recurring.yml for production and staging" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)

    %w[production staging].each do |env|
      expect(config.dig(env, "job_order_draft_sweep", "class")).to eq("JobOrderDraftSweepJob")
    end
  end
end
