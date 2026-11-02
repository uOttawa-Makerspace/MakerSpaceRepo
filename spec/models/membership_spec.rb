# frozen_string_literal: true

require "rails_helper"

RSpec.describe Membership, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :regular_user) }
  let(:tier) { create(:membership_tier, title_en: "1 Semester Membership", title_fr: "Adhesion", duration: 120, internal_price: 25, external_price: 40) }

  it { should belong_to(:user) }
  it { should belong_to(:membership_tier) }

  describe "status enum" do
    it "defaults NEW rows to 'pending' (enum default wins over the column default 'paid')" do
      expect(Membership.new.status).to eq("pending")
      expect(Membership.columns_hash["status"].default).to eq("paid") # DB default; the enum default shadows it
    end

    it "knows pending/paid/failed/revoked and rejects anything else" do
      expect(Membership.statuses.keys).to eq(%w[pending paid failed revoked])
      expect { Membership.new(status: "bogus") }.to raise_error(ArgumentError)
    end

    it "exposes predicate and bang helpers" do
      m = create(:membership, user: user, membership_tier: tier, status: "pending")
      expect(m).to be_pending
      m.paid!
      expect(m.reload).to be_paid
    end
  end

  describe "before_create :set_dates" do
    it "starts now and ends `duration` DAYS later when the user has no active membership" do
      freeze = Time.utc(2026, 1, 10, 15)
      travel_to(freeze) do
        m = Membership.create!(user: user, membership_tier: tier)
        expect(m.start_date).to eq(freeze)
        expect(m.end_date).to eq(Time.zone.at(freeze) + 120.days)
      end
    end

    it "stacks after the latest ACTIVE (paid, unexpired) membership" do
      base_end = 10.days.from_now.change(usec: 0)
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: base_end)
      m = Membership.create!(user: user, membership_tier: tier)
      expect(m.start_date).to be_within(1.second).of(base_end)
      expect(m.end_date).to be_within(1.second).of(base_end + 120.days)
    end

    it "does not stack after pending, revoked or expired memberships" do
      create(:membership, user: user, membership_tier: tier, status: "pending", end_date: 10.days.from_now)
      create(:membership, user: user, membership_tier: tier, status: "revoked", end_date: 10.days.from_now)
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 1.day.ago)
      m = Membership.create!(user: user, membership_tier: tier)
      expect(m.start_date).to be_within(5.seconds).of(Time.current)
    end

    it "keeps explicitly given dates" do
      s = 2.days.from_now.change(usec: 0)
      m = Membership.create!(user: user, membership_tier: tier, start_date: s, end_date: s + 3.days)
      expect([m.start_date, m.end_date]).to eq([s, s + 3.days])
    end

    it "computes the dates once, at creation: marking paid later does not move them" do
      m = Membership.create!(user: user, membership_tier: tier)
      original = m.slice(:start_date, :end_date)
      travel_to(30.days.from_now) { m.paid! }
      expect(m.reload.slice(:start_date, :end_date)).to eq(original)
    end
  end

  describe ".active scope and #active?" do
    it "includes only paid memberships whose end_date is in the future, newest end first" do
      soon = create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 2.days.from_now)
      later = create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 9.days.from_now)
      create(:membership, user: user, membership_tier: tier, status: "pending", end_date: 9.days.from_now)
      create(:membership, user: user, membership_tier: tier, status: "revoked", end_date: 9.days.from_now)
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 1.second.ago)
      expect(Membership.active.to_a).to eq([later, soon])
      expect(later.active?).to be(true)
      expect(Membership.new(end_date: 1.day.ago, status: "paid").active?).to be(false)
      expect(Membership.new(end_date: 1.day.from_now, status: "revoked").active?).to be(false)
    end

    it "is exposed per user by User#active_membership" do
      m = create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 5.days.from_now)
      expect(user.active_membership).to eq(m)
      expect(create(:user, :regular_user).active_membership).to be_nil
    end
  end

  describe ".calculate_end_date" do
    it "is now without an active membership, else the latest active end_date" do
      expect(Membership.calculate_end_date(user)).to be_within(5.seconds).of(Time.current)
      e = 7.days.from_now.change(usec: 0)
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: e)
      expect(Membership.calculate_end_date(user)).to be_within(1.second).of(e)
    end
  end

  describe "tier delegation and faculty flag" do
    it "delegates duration and renders the title for the current locale" do
      m = Membership.new(user: user, membership_tier: tier)
      expect(m.duration).to eq(120)
      expect(m.membership_title).to eq("1 Semester Membership")
      I18n.with_locale(:fr) { expect(m.membership_title).to eq("Adhesion") }
    end

    it "#faculty? matches 'faculty' anywhere in the English title, any case" do
      expect(Membership.new(membership_tier: build(:membership_tier, title_en: "Faculty Membership")).faculty?).to be(true)
      expect(Membership.new(membership_tier: build(:membership_tier, title_en: "FACULTY of Eng")).faculty?).to be(true)
      expect(Membership.new(membership_tier: tier).faculty?).to be(false)
    end
  end

  describe "Shopify draft-order seam" do
    it "tags drafts with the env-specific membership tag and builds the line item from the user's price" do
      expect(Membership.shopify_draft_order_key_name).to eq("membership")
      expect(Membership.draft_order_operating_tag).to eq("makerepo_test_membership")
      m = Membership.new(user: build(:user, identity: "definitely_not_internal"), membership_tier: tier)
      expect(m.shopify_draft_order_line_items)
        .to eq([{ originalUnitPrice: "40.0", quantity: 1, title: "1 Semester Membership" }])
    end

    it "#checkout_link returns the invoice URL of the (stubbed) draft order" do
      stub_shopify_admin!
      m = create(:membership, user: user, membership_tier: tier, status: "pending")
      expect(m.checkout_link).to eq("https://shop.example.test/invoices/abc")
      expect(m.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
    end

    it "#shopify_is_paid reflects the draft order's fullyPaid flag" do
      fake = stub_shopify_admin!
      m = create(:membership, user: user, membership_tier: tier, shopify_draft_order_id: "gid://shopify/DraftOrder/9001")
      expect(m.shopify_is_paid).to be(false)
      fake.fully_paid = true
      expect(m.shopify_is_paid).to be(true)
    end
  end

  describe "gating" do
    it "membership only drives display/labels: User#has_active_membership? mirrors Membership.active and nothing else gates on it" do
      expect(user.has_active_membership?).to be_falsey
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 5.days.from_now)
      expect(user.has_active_membership?).to be_truthy
      Membership.update_all(status: "revoked")
      expect(user.reload.has_active_membership?).to be_falsey
    end
  end
end
