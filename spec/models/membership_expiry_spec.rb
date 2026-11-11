# frozen_string_literal: true

require "rails_helper"

# Closing checkouts nobody paid: the draft order is deleted and the row is marked failed, never destroyed.
RSpec.describe Membership, "expiry of stale pending memberships", type: :model do
  let!(:fake) { stub_shopify_admin! }
  let(:member) { create(:user, :regular_user) }
  let(:tier) { create(:membership_tier, title_en: "1 Semester Membership", duration: 120) }
  let(:gid) { fake.draft_id }

  # `age`: how long ago the checkout was last touched.
  def pending_membership(age:, draft: gid, user: member)
    create(:membership, user: user, membership_tier: tier, status: "pending", start_date: nil, end_date: nil,
                        shopify_draft_order_id: draft, created_at: age.ago, updated_at: age.ago)
  end

  it "deletes the draft of a pending membership older than a week and marks the row expired, keeping it" do
    stale = pending_membership(age: 8.days)

    expect(Membership.expire_stale_pending!).to eq(expired: 1)

    expect(fake.deleted_ids).to eq([gid])
    expect(stale.reload).to have_attributes(status: "expired", shopify_draft_order_id: gid)
  end

  it "leaves a pending membership younger than the threshold alone" do
    fresh = pending_membership(age: 6.days)

    expect(Membership.expire_stale_pending!).to eq({})

    expect(fake.calls).to be_empty
    expect(fresh.reload).to be_pending
  end

  it "touches no paid, revoked, failed or expired membership, however old" do
    %w[paid revoked failed expired].each do |status|
      create(:membership, user: member, membership_tier: tier, status: status, shopify_draft_order_id: gid, created_at: 30.days.ago, updated_at: 30.days.ago)
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
    expect(stale.reload).to be_expired
  end

  it "expires a stale pending membership that never got a draft without calling Shopify" do
    stale = pending_membership(age: 8.days, draft: nil)

    expect(Membership.expire_stale_pending!).to eq(expired: 1)

    expect(fake.calls).to be_empty
    expect(stale.reload).to be_expired
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
    expect(other.reload).to be_expired
  end

  it "marks nothing and deletes nothing when the draft completes between the check and the delete" do
    fake.lose_delete_race = :paid
    stale = pending_membership(age: 8.days)

    expect(Membership.expire_stale_pending!).to eq(paid: 1)

    expect(stale.reload).to be_pending
  end

  it "does not close a checkout the member came back to after the run picked it" do
    stale = pending_membership(age: 8.days)
    loaded = Membership.find(stale.id)
    stale.touch

    expect(loaded.expire_if_stale).to eq(:changed)

    expect(fake.calls).to be_empty
    expect(stale.reload).to be_pending
  end

  it "keeps the checkout of a member who buys again, whatever the age of the row, and serves a live draft" do
    stale = pending_membership(age: 8.days)

    expect(Membership.begin_purchase(member, tier.id)).to eq(fake.invoice_url)
    expect(Membership.expire_stale_pending!).to eq({})

    expect(fake.deleted_ids).to be_empty
    expect(member.memberships.pending.pluck(:id)).to eq([stale.id])
  end

  it "starts a new pending membership when the one being checked out was expired before its draft was stored" do
    old = pending_membership(age: 1.day, draft: nil)
    expired_once = false
    fake.on_query = lambda { |query, _|
      next if expired_once || !query.include?("draftOrderCreate")

      expired_once = true
      Membership.where(id: old.id).update_all(status: "expired")
    }

    expect(Membership.begin_purchase(member, tier.id)).to eq(fake.invoice_url)

    expect(old.reload).to be_expired
    expect(member.memberships.pending.pluck(:shopify_draft_order_id)).to eq([gid])
    expect(member.memberships.count).to eq(2)
  end

  it "makes no second pending membership when the one being checked out was paid before its draft was stored" do
    claimed = pending_membership(age: 1.day, draft: nil)
    fake.on_query = lambda { |query, _|
      Membership.where(id: claimed.id).update_all(status: "paid") if query.include?("draftOrderCreate")
    }

    expect { Membership.begin_purchase(member, tier.id) }.to raise_error(/no draft order to serve/)

    expect(member.memberships.pending).to be_empty
    expect(member.memberships.count).to eq(1)
  end

  it "does not overwrite a membership that was paid while the run was in progress" do
    stale = pending_membership(age: 8.days)
    fake.on_query = ->(query, _) { Membership.where(id: stale.id).update_all(status: "paid") if query.include?("draftOrderDelete") }

    expect(Membership.find(stale.id).expire_if_stale).to eq(:changed)

    expect(stale.reload).to be_paid
  end

  it "does not close a checkout that got a new draft while the run was in progress" do
    stale = pending_membership(age: 8.days)
    fake.on_query = lambda { |query, _|
      Membership.where(id: stale.id).update_all(shopify_draft_order_id: "gid://shopify/DraftOrder/2") if query.include?("draftOrderDelete")
    }

    expect(Membership.find(stale.id).expire_if_stale).to eq(:changed)

    expect(stale.reload).to be_pending
  end

  it "is safe to run twice" do
    stale = pending_membership(age: 8.days)

    expect(Membership.expire_stale_pending!).to eq(expired: 1)
    expect(Membership.expire_stale_pending!).to eq({})

    expect(fake.deleted_ids).to eq([gid])
    expect(stale.reload).to be_expired
  end

  it "does not apply a late payment to an expired checkout" do
    stale = pending_membership(age: 8.days)
    Membership.expire_stale_pending!

    expect(stale.reload.mark_paid_if_pending).to be(false)
    expect(stale.reload).to be_expired
  end

  it "lets the member buy again after the checkout expired, on a new pending row" do
    pending_membership(age: 8.days)
    Membership.expire_stale_pending!

    expect { Membership.claim_pending(member, tier.id) }.to change { member.memberships.pending.count }.from(0).to(1)
    expect(member.memberships.count).to eq(2)
  end
end
