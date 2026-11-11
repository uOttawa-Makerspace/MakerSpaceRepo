# frozen_string_literal: true

require "rails_helper"

# Closing checkouts nobody paid: the draft order is deleted and the row is marked failed, never destroyed.
RSpec.describe Membership, "expiry of stale pending memberships", type: :model do
  let!(:fake) { stub_shopify_admin! }
  let(:member) { create(:user, :regular_user) }
  let(:tier) { create(:membership_tier, title_en: "1 Semester Membership", duration: 120) }
  let(:gid) { fake.draft_id }

  def pending_membership(age:, draft: gid, user: member)
    create(:membership, user: user, membership_tier: tier, status: "pending", start_date: nil, end_date: nil,
                        shopify_draft_order_id: draft, created_at: age.ago)
  end

  it "deletes the draft of a pending membership older than a week and marks the row failed, keeping it" do
    stale = pending_membership(age: 8.days)

    expect(Membership.expire_stale_pending!).to eq(expired: 1)

    expect(fake.deleted_ids).to eq([gid])
    expect(stale.reload).to have_attributes(status: "failed", shopify_draft_order_id: gid)
  end

  it "leaves a pending membership younger than the threshold alone" do
    fresh = pending_membership(age: 6.days)

    expect(Membership.expire_stale_pending!).to eq({})

    expect(fake.calls).to be_empty
    expect(fresh.reload).to be_pending
  end

  it "touches no paid, revoked or failed membership, however old" do
    %w[paid revoked failed].each do |status|
      create(:membership, user: member, membership_tier: tier, status: status, shopify_draft_order_id: gid, created_at: 30.days.ago)
    end

    expect(Membership.expire_stale_pending!).to eq({})
    expect(fake.calls).to be_empty
  end

  it "marks nothing and deletes nothing when the draft is paid" do
    fake.draft_statuses[gid] = "COMPLETED"
    stale = pending_membership(age: 30.days)

    expect(Membership.expire_stale_pending!).to eq(paid: 1)

    expect(fake.deleted_ids).to be_empty
    expect(stale.reload).to be_pending
  end

  it "counts a draft already gone from Shopify as deleted" do
    fake.missing_ids << gid
    stale = pending_membership(age: 8.days)

    expect(Membership.expire_stale_pending!).to eq(expired: 1)

    expect(fake.deleted_ids).to be_empty
    expect(stale.reload).to be_failed
  end

  it "fails a stale pending membership that never got a draft without calling Shopify" do
    stale = pending_membership(age: 8.days, draft: nil)

    expect(Membership.expire_stale_pending!).to eq(expired: 1)

    expect(fake.calls).to be_empty
    expect(stale.reload).to be_failed
  end

  it "keeps the row pending when Shopify refuses to delete a still payable draft" do
    fake.delete_user_errors = [{ "field" => "id", "message" => "nope" }]
    stale = pending_membership(age: 8.days)

    expect(Membership.expire_stale_pending!).to eq(open: 1)

    expect(stale.reload).to be_pending
  end

  it "reports a Shopify outage, keeps the row pending and carries on with the next one" do
    fake.status = 502
    stale = pending_membership(age: 8.days)
    other = pending_membership(age: 9.days, draft: nil, user: create(:user, :regular_user))
    expect(Rails.error).to receive(:report).once

    expect(Membership.expire_stale_pending!).to eq(error: 1, expired: 1)

    expect(stale.reload).to be_pending
    expect(other.reload).to be_failed
  end

  it "does not overwrite a membership that was paid while the run was in progress" do
    stale = pending_membership(age: 8.days)
    fake.on_query = ->(query, _) { Membership.where(id: stale.id).update_all(status: "paid") if query.include?("draftOrderDelete") }

    expect(Membership.find(stale.id).expire_stale).to eq(:changed)

    expect(stale.reload).to be_paid
  end

  it "does not close a checkout that got a new draft while the run was in progress" do
    stale = pending_membership(age: 8.days)
    fake.on_query = lambda { |query, _|
      Membership.where(id: stale.id).update_all(shopify_draft_order_id: "gid://shopify/DraftOrder/2") if query.include?("draftOrderDelete")
    }

    expect(Membership.find(stale.id).expire_stale).to eq(:changed)

    expect(stale.reload).to be_pending
  end

  it "is safe to run twice" do
    stale = pending_membership(age: 8.days)

    expect(Membership.expire_stale_pending!).to eq(expired: 1)
    expect(Membership.expire_stale_pending!).to eq({})

    expect(fake.deleted_ids).to eq([gid])
    expect(stale.reload).to be_failed
  end

  it "does not apply a late payment to an expired checkout" do
    stale = pending_membership(age: 8.days)
    Membership.expire_stale_pending!

    expect(stale.reload.mark_paid_if_pending).to be(false)
    expect(stale.reload).to be_failed
  end

  it "lets the member buy again after the checkout expired, on a new pending row" do
    pending_membership(age: 8.days)
    Membership.expire_stale_pending!

    expect { Membership.claim_pending(member, tier.id) }.to change { member.memberships.pending.count }.from(0).to(1)
    expect(member.memberships.count).to eq(2)
  end
end
