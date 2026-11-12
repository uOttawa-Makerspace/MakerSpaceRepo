# frozen_string_literal: true

require "rails_helper"

RSpec.describe JobOrderDraftSweepJob, type: :job do

  include ShopSpecHelpers
  include JobOrderSpecHelpers

  before { seed_job_statuses! }

  let!(:shopify) { stub_shopify_admin! }

  it "runs JobOrder::DraftSweep and is quiet when nothing is unresolved" do
    expect { described_class.perform_now }.not_to raise_error
  end

  it "completes while a draft is unresolved and reports once per kind of sweep (it must not fail every hour for the same draft)" do
    shopify.status = 502
    summaries = []
    allow(Rails.error).to receive(:report) { |error, **_| summaries << error.message }

    expect { described_class.perform_now }.not_to raise_error
    expect(summaries).to contain_exactly(JobOrder::DraftSweep::SUMMARY_MESSAGE, LockerRental::DraftSweep::SUMMARY_MESSAGE)
  end

  it "still runs the locker sweep when the job-order sweep raises" do
    rental = create(:locker_rental, :await_payment)
    gid = "gid://shopify/DraftOrder/1"
    shopify.draft_pages = [[{ "id" => gid, "status" => "OPEN", "createdAt" => 2.hours.ago.iso8601,
                              "tags" => [LockerRental.draft_order_operating_tag, "locker_rental:#{rental.id}"] }]]
    allow(JobStatus).to receive(:completed).and_raise(JobStatus::Missing)
    allow(Rails.error).to receive(:report)

    expect { described_class.perform_now }.not_to raise_error
    expect(shopify.deleted_ids).to eq([gid])
  end

  it "also closes the old unreferenced locker drafts" do
    rental = create(:locker_rental, :await_payment)
    gid = "gid://shopify/DraftOrder/1"
    shopify.draft_pages = [[{ "id" => gid, "status" => "OPEN", "createdAt" => 2.hours.ago.iso8601,
                              "tags" => [LockerRental.draft_order_operating_tag, "locker_rental:#{rental.id}"] }]]

    described_class.perform_now

    expect(shopify.deleted_ids).to eq([gid])
  end

  it "is scheduled in config/recurring.yml for production and staging" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)

    %w[production staging].each do |env|
      expect(config.dig(env, "job_order_draft_sweep", "class")).to eq("JobOrderDraftSweepJob")
    end
  end
end
