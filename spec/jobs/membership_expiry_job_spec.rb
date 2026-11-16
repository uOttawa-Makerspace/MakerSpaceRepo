# frozen_string_literal: true

require "rails_helper"

RSpec.describe MembershipExpiryJob, type: :job do
  let!(:fake) { stub_shopify_admin! }

  it "expires stale pending memberships and keeps the rows" do
    membership = create(:membership, status: "pending", start_date: nil, end_date: nil,
                                     shopify_draft_order_id: fake.draft_id, created_at: 8.days.ago, updated_at: 8.days.ago)

    described_class.perform_now

    expect(fake.deleted_ids).to eq([fake.draft_id])
    expect(membership.reload).to be_expired
  end

  it "logs what it did" do
    create(:membership, status: "pending", start_date: nil, end_date: nil, shopify_draft_order_id: fake.draft_id,
                        created_at: 8.days.ago, updated_at: 8.days.ago)
    allow(Rails.logger).to receive(:info)

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with("[MembershipExpiryJob] expired: 1")
  end

  it "does nothing when no membership is stale" do
    fresh = create(:membership, status: "pending", start_date: nil, end_date: nil, shopify_draft_order_id: fake.draft_id)

    described_class.perform_now

    expect(fake.calls).to be_empty
    expect(fresh.reload).to be_pending
  end
end
