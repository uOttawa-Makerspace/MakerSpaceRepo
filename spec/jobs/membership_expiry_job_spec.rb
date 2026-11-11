# frozen_string_literal: true

require "rails_helper"

RSpec.describe MembershipExpiryJob, type: :job do
  let!(:fake) { stub_shopify_admin! }

  it "expires stale pending memberships and keeps the rows" do
    membership = create(:membership, status: "pending", start_date: nil, end_date: nil,
                                     shopify_draft_order_id: fake.draft_id, created_at: 8.days.ago)

    described_class.perform_now

    expect(fake.deleted_ids).to eq([fake.draft_id])
    expect(membership.reload).to be_failed
  end

  it "completes when there is nothing to do" do
    expect { described_class.perform_now }.not_to raise_error
  end
end
