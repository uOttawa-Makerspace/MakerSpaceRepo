# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "memberships:pending_duplicates" do
  let(:tier) { create(:membership_tier) }
  let(:other_tier) { create(:membership_tier, title_en: "Other tier") }
  let(:member) { create(:user, :regular_user) }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("memberships:pending_duplicates")
    Rake::Task["memberships:pending_duplicates"].reenable
  end

  def pending(user, tier_for)
    create(:membership, user: user, membership_tier: tier_for, status: "pending", start_date: nil, end_date: nil,
                        shopify_draft_order_id: "gid://shopify/DraftOrder/#{(@draft_seq = @draft_seq.to_i + 1)}")
  end

  def run = Rake::Task["memberships:pending_duplicates"].invoke

  it "lists each member and tier pair with more than one pending row, with counts and ids" do
    rows = [pending(member, tier), pending(member, tier), pending(member, tier)]

    expect { run }.to output(
      /user #{member.id}, tier #{tier.id}: 3 pending \(ids #{rows.map(&:id).sort.join(", ")}\).*1 pair, 3 pending memberships/m
    ).to_stdout
  end

  it "marks the lowest id as the row kept and the others as extra, with created time and stored draft id" do
    first = pending(member, tier)
    second = create(:membership, user: member, membership_tier: tier, status: "pending", start_date: nil, end_date: nil,
                                 shopify_draft_order_id: nil)
    kept = "membership #{first.id} keep created #{first.created_at.utc.iso8601} " \
           "updated #{first.updated_at.utc.iso8601} draft #{first.shopify_draft_order_id}"

    expect { run }.to output(/#{Regexp.escape(kept)}\n.*membership #{second.id} extra created \S+ updated \S+ draft none/m).to_stdout
  end

  it "lists a pair with exactly two pending rows" do
    rows = [pending(member, tier), pending(member, tier)]

    expect { run }.to output(/user #{member.id}, tier #{tier.id}: 2 pending \(ids #{rows.map(&:id).sort.join(", ")}\)/).to_stdout
  end

  it "ignores single pending rows and rows that are not pending" do
    pending(member, tier)
    pending(member, other_tier)
    create(:membership, user: member, membership_tier: tier, status: "failed")
    create(:membership, user: member, membership_tier: tier, status: "paid")

    expect { run }.to output(/no member and tier pair has more than one pending membership/).to_stdout
  end

  it "changes nothing and calls no outside service" do
    pending(member, tier)
    pending(member, tier)

    expect { expect { run }.to output.to_stdout }.not_to(change { Membership.order(:id).pluck(:id, :status, :shopify_draft_order_id, :updated_at) })
  end
end
