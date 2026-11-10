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

  describe "dates" do
    it "a pending membership has none until it is paid" do
      m = Membership.create!(user: user, membership_tier: tier)
      expect([m.start_date, m.end_date]).to eq([nil, nil])
    end

    it "a paid membership made without dates starts now and ends `duration` DAYS later" do
      freeze = Time.utc(2026, 1, 10, 15)
      travel_to(freeze) do
        m = Membership.create!(user: user, membership_tier: tier, status: "paid")
        expect(m.start_date).to eq(freeze)
        expect(m.end_date).to eq(Time.zone.at(freeze) + 120.days)
      end
    end

    it "a paid membership made without dates stacks after the latest ACTIVE (paid, unexpired) one" do
      base_end = 10.days.from_now.change(usec: 0)
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: base_end)
      m = Membership.create!(user: user, membership_tier: tier, status: "paid")
      expect(m.start_date).to be_within(1.second).of(base_end)
      expect(m.end_date).to be_within(1.second).of(base_end + 120.days)
    end

    it "does not stack after pending, revoked or expired memberships" do
      create(:membership, user: user, membership_tier: tier, status: "pending", end_date: 10.days.from_now)
      create(:membership, user: user, membership_tier: tier, status: "revoked", end_date: 10.days.from_now)
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 1.day.ago)
      m = Membership.create!(user: user, membership_tier: tier, status: "paid")
      expect(m.start_date).to be_within(5.seconds).of(Time.current)
    end

    it "keeps explicitly given dates" do
      s = 2.days.from_now.change(usec: 0)
      m = Membership.create!(user: user, membership_tier: tier, status: "paid", start_date: s, end_date: s + 3.days)
      expect([m.start_date, m.end_date]).to eq([s, s + 3.days])
    end
  end

  describe "#mark_paid_if_pending dates" do
    let(:clicked) { Time.utc(2026, 1, 1, 12) }
    let(:membership) { travel_to(clicked) { Membership.create!(user: user, membership_tier: tier) } }

    it "starts the membership when it is paid, not when it was clicked" do
      membership
      travel_to(clicked + 9.days) do
        expect(membership.mark_paid_if_pending).to be(true)
        membership.reload
        expect(membership).to be_paid
        expect(membership.start_date).to eq(clicked + 9.days)
        expect(membership.end_date).to eq(Time.zone.at(clicked + 9.days) + 120.days)
      end
    end

    it "starts after the member's active membership when there is one" do
      membership
      current_end = clicked + 29.days
      travel_to(clicked + 9.days) do
        create(:membership, user: user, membership_tier: tier, status: "paid", start_date: clicked - 30.days, end_date: current_end)
        membership.mark_paid_if_pending
        membership.reload
        expect(membership.start_date).to eq(current_end)
        expect(membership.end_date).to eq(Time.zone.at(current_end) + 120.days)
      end
    end

    it "stacks two pending memberships paid one after the other" do
      other = travel_to(clicked) { Membership.create!(user: user, membership_tier: create(:membership_tier, duration: 30)) }
      membership
      travel_to(clicked + 2.days) do
        membership.mark_paid_if_pending
        other.mark_paid_if_pending
      end
      expect(other.reload.start_date).to eq(membership.reload.end_date)
      expect(other.end_date).to eq(Time.zone.at(membership.end_date) + 30.days)
    end

    it "changes nothing when the membership is no longer pending" do
      membership.update_column(:status, "revoked")
      expect { membership.mark_paid_if_pending }.not_to(change { membership.reload.attributes })
    end
  end

  describe ".grant!" do
    it "makes a paid membership of the tier's duration, stacked after the latest active one" do
      base_end = 10.days.from_now.change(usec: 0)
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: base_end)
      m = Membership.grant!(user, tier)
      expect(m).to be_paid
      expect(m.start_date).to eq(base_end)
      expect(m.end_date).to eq(Time.zone.at(base_end) + 120.days)
    end
  end

  describe ".active scope and #active?" do
    it "includes only paid memberships whose end_date is in the future, newest end first" do
      soon = create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 2.days.from_now)
      later = create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 9.days.from_now)
      create(:membership, user: user, membership_tier: tier, status: "pending", end_date: 9.days.from_now)
      create(:membership, user: user, membership_tier: tier, status: "revoked", end_date: 9.days.from_now)
      create(:membership, user: user, membership_tier: tier, status: "failed", end_date: 9.days.from_now)
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

    it "the concern's draft order and paid state are returned on first use, not nil" do
      fake = stub_shopify_admin!
      fake.fully_paid = true
      m = create(:membership, user: user, membership_tier: tier, status: "pending")
      expect(m.send(:shopify_draft_order)).to include("invoiceUrl" => fake.invoice_url)
      expect(m.reload.shopify_draft_order_id).to eq(fake.draft_id)

      fresh = create(:membership, user: user, membership_tier: tier, status: "pending")
      expect(fresh.shopify_is_paid).to be(true)
    end

    it "#checkout_link is asked once per membership" do
      fake = stub_shopify_admin!
      m = create(:membership, user: user, membership_tier: tier, status: "pending")
      2.times { m.checkout_link }
      expect(fake.calls.size).to eq(2) # one create, one fetch
    end

    it "#checkout_link raises when no draft order exists after one was created" do
      stub_shopify_admin!
      m = create(:membership, user: user, membership_tier: tier, status: "pending")
      allow(m).to receive(:create_and_store_remote_draft_order)
      expect { m.checkout_link }.to raise_error(/no draft order/)
    end

    it "#checkout_link raises when Shopify does not answer the draft order check" do
      fake = stub_shopify_admin!
      m = create(:membership, user: user, membership_tier: tier, status: "pending", shopify_draft_order_id: "gid://shopify/DraftOrder/9001")
      fake.status = 500
      expect { m.checkout_link }.to raise_error(/did not answer/)
    end

    it "#checkout_link is nil for a draft Shopify no longer has" do
      fake = stub_shopify_admin!
      fake.missing_ids << "gid://shopify/DraftOrder/9001"
      m = create(:membership, user: user, membership_tier: tier, status: "pending", shopify_draft_order_id: "gid://shopify/DraftOrder/9001")
      expect(m.checkout_link).to be_nil
    end

    describe ".begin_purchase" do
      let!(:fake) { stub_shopify_admin! }
      let(:old_id) { "gid://shopify/DraftOrder/9001" }
      let(:new_id) { "gid://shopify/DraftOrder/9002" }

      def reprice!
        tier.update!(external_price: 55)
        fake.draft_id = new_id
      end

      it "returns the invoice URL of the user's pending checkout, reusing its draft while the price is unchanged" do
        expect(Membership.begin_purchase(user, tier.id)).to eq(fake.invoice_url)
        expect(Membership.begin_purchase(user, tier.id)).to eq(fake.invoice_url)
        expect(user.memberships.count).to eq(1)
        expect(fake.calls.count { |c| c[:query].include?("draftOrderCreate") }).to eq(1)
        expect(fake.deleted_ids).to be_empty
      end

      it "replaces the draft of a checkout whose price has changed: the old one is deleted first, then a new one made" do
        Membership.begin_purchase(user, tier.id)
        reprice!

        expect(Membership.begin_purchase(user, tier.id)).to eq(fake.invoice_url)

        membership = user.memberships.sole
        expect(membership).to be_pending
        expect(membership.shopify_draft_order_id).to eq(new_id)
        expect(fake.deleted_ids).to eq([old_id])
        queries = fake.calls.map { |c| c[:query][/draftOrder(Create|Delete)/] }.compact
        expect(queries).to eq(%w[draftOrderCreate draftOrderDelete draftOrderCreate])
        expect(fake.calls.select { |c| c[:query].include?("draftOrderCreate") }.last[:variables].dig(:input, :lineItems, 0, :originalUnitPrice)).to eq("55.0")
      end

      it "keeps serving the old draft, and reports it, when the old draft cannot be deleted" do
        Membership.begin_purchase(user, tier.id)
        reprice!
        fake.delete_user_errors = [{ "field" => "id", "message" => "not deletable" }]
        allow(Rails.error).to receive(:report)

        expect(Membership.begin_purchase(user, tier.id)).to eq(fake.invoice_url)

        expect(Rails.error).to have_received(:report)
        membership = user.memberships.sole
        expect(membership).to be_pending
        expect(membership.shopify_draft_order_id).to eq(old_id)
        expect(fake.calls.count { |c| c[:query].include?("draftOrderCreate") }).to eq(1)
      end

      it "does not replace a draft that is already paid, whatever its price" do
        Membership.begin_purchase(user, tier.id)
        reprice!
        fake.draft_statuses[old_id] = "COMPLETED"

        expect(Membership.begin_purchase(user, tier.id)).to eq(fake.invoice_url)

        expect(user.memberships.sole.shopify_draft_order_id).to eq(old_id)
        expect(fake.deleted_ids).to be_empty
        expect(fake.calls.count { |c| c[:query].include?("draftOrderCreate") }).to eq(1)
      end

      it "marks the checkout failed and starts a new one when its draft is gone" do
        Membership.begin_purchase(user, tier.id)
        fake.missing_ids << old_id
        fake.draft_id = new_id

        Membership.begin_purchase(user, tier.id)

        expect(user.memberships.failed.sole.shopify_draft_order_id).to eq(old_id)
        expect(user.memberships.pending.sole.shopify_draft_order_id).to eq(new_id)
      end

      it "does not fail a checkout whose draft was replaced by another request, and uses that checkout" do
        Membership.begin_purchase(user, tier.id)
        stale = Membership.find(user.memberships.sole.id)
        stale.update_column(:shopify_draft_order_id, old_id)
        Membership.find(stale.id).update_column(:shopify_draft_order_id, new_id)
        fake.missing_ids << old_id

        expect(stale.checkout_link).to be_nil

        expect(stale.reload).to be_pending
        expect(Membership.begin_purchase(user, tier.id)).to eq(fake.invoice_url)
        expect(user.memberships.count).to eq(1)
      end

      it "raises rather than loop when the checkout keeps changing under it" do
        allow_any_instance_of(Membership).to receive(:checkout_link).and_return(nil)
        expect { Membership.begin_purchase(user, tier.id) }.to raise_error(/did not settle/)
      end
    end

    context "when the new draft order cannot be kept" do
      let!(:fake) { stub_shopify_admin! }
      let!(:m) { create(:membership, user: user, membership_tier: tier, status: "pending") }
      let(:reports) { [] }

      before { allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] } }

      it "deletes it and re-raises when storing its id fails" do
        allow(m).to receive(:adopt_draft).and_raise(ActiveRecord::LockWaitTimeout, "x")
        expect { m.checkout_link }.to raise_error(ActiveRecord::LockWaitTimeout)
        expect(fake.deleted_ids).to eq(["gid://shopify/DraftOrder/9001"])
        expect(m.reload.shopify_draft_order_id).to be_nil
      end

      it "deletes it when another request stored an id first" do
        m.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/1")
        m2 = Membership.find(m.id)
        m2.send(:create_shopify_draft_order)
        expect(fake.deleted_ids).to eq(["gid://shopify/DraftOrder/9001"])
        expect(m.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/1")
      end

      it "returns the winner's invoice URL, fetches the winner's draft and deletes its own when another request stores first" do
        winner = "gid://shopify/DraftOrder/1"
        allow(m).to receive(:create_remote_draft_order).and_wrap_original do |original, *args|
          original.call(*args).tap { Membership.find(m.id).update_column(:shopify_draft_order_id, winner) }
        end
        fake.invoice_url = "https://shop.example.test/invoices/winner"

        expect(m.checkout_link).to eq("https://shop.example.test/invoices/winner")
        expect(fake.calls.last[:variables][:id]).to eq(winner)
        expect(fake.deleted_ids).to eq(["gid://shopify/DraftOrder/9001"])
        expect(m.reload.shopify_draft_order_id).to eq(winner)
      end

      it "does not keep a draft for a membership that is no longer pending" do
        m.update_column(:status, "revoked")
        Membership.find(m.id).send(:create_shopify_draft_order)
        expect(fake.deleted_ids).to eq(["gid://shopify/DraftOrder/9001"])
        expect(m.reload.shopify_draft_order_id).to be_nil
      end

      it "reports, and does not raise, when Shopify will not delete the unused draft" do
        fake.delete_user_errors = [{ "field" => "id", "message" => "not deletable" }]
        m.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/1")
        expect { Membership.find(m.id).send(:create_shopify_draft_order) }.not_to raise_error
        error, opts = reports.first
        expect(error.message).to include("did not delete the unused draft order")
        expect(opts[:context]).to include(membership_id: m.id, step: "delete_unused_shopify_draft_order")
      end
    end

    describe "status changes from pending" do
      %w[paid failed revoked].each do |status|
        it "mark_failed_if_pending and mark_paid_if_pending leave a #{status} membership as it is" do
          m = create(:membership, user: user, membership_tier: tier, status: status)
          expect(m.mark_failed_if_pending).to be(false)
          expect(m.mark_paid_if_pending).to be(false)
          expect(m.reload.status).to eq(status)
        end
      end

      it "mark_failed_if_pending fails a pending membership" do
        m = create(:membership, user: user, membership_tier: tier, status: "pending")
        expect(m.mark_failed_if_pending).to be(true)
        expect(m.reload.status).to eq("failed")
      end
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
      %w[revoked pending failed].each do |status|
        Membership.update_all(status: status)
        expect(user.reload.has_active_membership?).to be_falsey
      end
    end
  end
end
