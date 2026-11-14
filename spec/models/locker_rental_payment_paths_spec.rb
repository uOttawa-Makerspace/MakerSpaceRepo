# frozen_string_literal: true

require "rails_helper"

# Pins every branch of the LockerRental payment, amount, mail and Shopify draft paths as they behave now:
# #record_payment, #locker_line_amount, #notification_mails (by delivered mail) and
# #sync_shopify_draft_order_after_commit (by the exact Shopify calls).
RSpec.describe LockerRental, type: :model do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before { ActionMailer::Base.deliveries.clear }

  def deliveries
    ActionMailer::Base.deliveries
  end

  describe "#record_payment status and hold reason" do
    let(:frozen) { Time.utc(2026, 10, 20, 12, 0, 0) }

    def pay(rental, id, **opts)
      payment = nil
      travel_to(frozen) { perform_enqueued_jobs { payment = rental.record_payment(shopify_order_id: id, **opts) } }
      payment
    end

    it "checks cancelled first, then the renter, then a duplicate charge" do
      cancelled_ineligible = create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }
      cancelled_ineligible.rented_by.deactivate!
      cancelled_ineligible = described_class.find(cancelled_ineligible.id)
      expect(pay(cancelled_ineligible, "p-1")).to have_attributes(status: "held", hold_reason: "rental_cancelled")

      paid_ineligible = create(:locker_rental, :active).tap { |r| r.update_column(:paid_at, 2.days.ago) }
      paid_ineligible.rented_by.deactivate!
      paid_ineligible = described_class.find(paid_ineligible.id)
      expect(pay(paid_ineligible, "p-2")).to have_attributes(status: "held", hold_reason: "renter_ineligible")

      paid = create(:locker_rental, :active).tap { |r| r.update_column(:paid_at, 2.days.ago) }
      expect(pay(paid, "p-3")).to have_attributes(status: "held", hold_reason: "already_paid")
    end

    it "stores every figure, the order id as a string, and resolved_at only for an applied payment" do
      rental = create(:locker_rental, :await_payment)
      applied = pay(rental, 7001, amount: "12.50", currency: "CAD", order_total: "20.00")
      expect(applied.reload).to have_attributes(
        shopify_order_id: "7001", amount: BigDecimal("12.50"), currency: "CAD", order_total: BigDecimal("20.00"),
        status: "applied", hold_reason: nil, paid_at: frozen, resolved_at: frozen
      )

      held = pay(create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }, 7002)
      expect(held.reload).to have_attributes(status: "held", resolved_at: nil, amount: nil, currency: nil, order_total: nil)
    end

    it "treats the same order id as a duplicate whether it arrives as a number or a string" do
      rental = create(:locker_rental, :await_payment)
      first = pay(rental, 7003)
      expect(pay(rental, "7003")).to be_nil
      expect(LockerPayment.where(shopify_order_id: "7003").pluck(:id)).to eq([first.id])
    end

    it "applies a payment on an active rental with no paid_at: stamps paid_at, no state change, no mail, no report" do
      rental = create(:locker_rental, :active)
      reports = []
      allow(Rails.error).to receive(:report) { |error, **| reports << error }
      payment = pay(rental, "7004", paid_at: frozen)
      expect(payment).to have_attributes(status: "applied")
      expect(rental.reload).to have_attributes(state: "active", paid_at: frozen)
      expect(deliveries).to be_empty
      expect(reports).to be_empty
    end

    it "for a rental that cannot be activated: held not_activatable, paid_at untouched, no mail, one held report" do
      rental = create(:locker_rental) # reviewing, no locker: cannot become active
      reports = []
      allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] }
      payment = pay(rental, "7005", paid_at: frozen)
      expect(payment.reload).to have_attributes(status: "held", hold_reason: "not_activatable", resolved_at: nil)
      expect(rental.reload).to have_attributes(state: "reviewing", paid_at: nil)
      expect(deliveries).to be_empty
      expect(reports.map { |error, _| error.class }).to eq([LockerPayment::Held])
      expect(reports.first.last[:context]).to include(locker_payment_id: payment.id, hold_reason: "not_activatable")
    end

    it "activates a reviewing rental that has a locker and a decider, and mails the renter once" do
      rental = create(:locker_rental, locker: create(:locker), decided_by: create(:user))
      payment = pay(rental, "7006", paid_at: frozen)
      expect(payment).to have_attributes(status: "applied")
      expect(rental.reload).to have_attributes(state: "active", paid_at: frozen)
      expect(deliveries.map { |m| [m.to, m.subject] })
        .to eq([[[rental.rented_by.email], "Locker #{rental.locker.specifier} has been assigned for you"]])
    end

    it "reports malformed figures for a held payment too" do
      rental = create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }
      reports = []
      allow(Rails.error).to receive(:report) { |error, **| reports << error.class }
      pay(rental, "7007", malformed_amounts: %w[amount])
      expect(reports).to eq([LockerPayment::Held, LockerPayment::MalformedPaymentAmount])
    end
  end

  describe "#locker_line_amount edges" do
    let(:rental) { create(:locker_rental, :await_payment) }
    let(:title) { "TEST locker on #{Rails.env} environment." }

    it "is nil for a rental without a locker, without building the expected line" do
      no_locker = create(:locker_rental)
      expect(no_locker).not_to receive(:shopify_draft_order_line_items)
      expect(no_locker.locker_line_amount([{ "title" => title, "price" => "5.00" }])).to be_nil
    end

    it "does not build the expected line when line_items is not an Array" do
      expect(rental).not_to receive(:shopify_draft_order_line_items)
      expect(rental.locker_line_amount({ "title" => title })).to be_nil
    end

    it "skips entries that are not a Hash" do
      expect(rental.locker_line_amount(["x", nil, 3, { "title" => title, "price" => "4.00" }])).to eq(BigDecimal("4.00"))
    end

    it "takes a missing or blank quantity as 1 and a missing price as 0" do
      expect(rental.locker_line_amount([{ "title" => title, "price" => "4.00" }])).to eq(BigDecimal("4.00"))
      expect(rental.locker_line_amount([{ "title" => title, "price" => "4.00", "quantity" => "" }])).to eq(BigDecimal("4.00"))
      expect(rental.locker_line_amount([{ "title" => title, "quantity" => 3 }])).to eq(BigDecimal("0"))
      expect(rental.locker_line_amount([{ "title" => title, "price" => "4.00", "quantity" => "2" }])).to eq(BigDecimal("8.00"))
    end

    it "rounds each price to cents before multiplying, and sums every matching line" do
      expect(rental.locker_line_amount([{ "title" => title, "price" => "3.335", "quantity" => 3 }])).to eq(BigDecimal("10.02"))
      lines = [{ "title" => title, "price" => "2.50", "quantity" => 1 }, { "title" => title, "price" => "1.25", "quantity" => 2 }]
      expect(rental.locker_line_amount(lines)).to eq(BigDecimal("5.00"))
    end

    it "raises ArgumentError when the discount makes the line negative" do
      expect { rental.locker_line_amount([{ "title" => title, "price" => "1.00", "total_discount" => "2.00" }]) }
        .to raise_error(ArgumentError)
    end

    it "matches by title outside production and ignores the variant" do
      expect(rental.locker_line_amount([{ "variant_id" => 1, "title" => "other", "price" => "4.00" }])).to be_nil
    end
  end

  describe "#notification_mails by delivered outcome" do
    def notify(rental)
      perform_enqueued_jobs { rental.notify_after_commit }
    end

    def sent
      deliveries.map { |m| [m.to, m.subject] }
    end

    it "mails the cancelled notice with no locker for a cancelled request that never had one" do
      rental = create(:locker_rental)
      rental.update!(state: :cancelled, decided_by: rental.rented_by)
      notify(rental)
      expect(sent).to eq([[[rental.rented_by.email], "Your locker rental request has been cancelled"]])
    end

    it "mails the request notice to staff when a rental is moved back to reviewing" do
      rental = create(:locker_rental, :active)
      rental.update!(state: :reviewing)
      notify(rental)
      expect(sent).to eq([[["ceed@uottawa.ca"], "New locker request"]])
    end

    it "names the old locker in the moved mail, and the new date when only the date moved" do
      rental = create(:locker_rental, :active, owned_until: 2.months.from_now)
      old_locker = rental.locker
      new_locker = create(:locker)
      rental.update!(locker: new_locker)
      notify(rental)
      expect(deliveries.size).to eq(1)
      body = deliveries.first.html_part ? deliveries.first.html_part.body.decoded : deliveries.first.body.decoded
      expect(body).to include("from locker #{old_locker.specifier}")
      expect(body).not_to include("now active until")

      deliveries.clear
      rental.update!(owned_until: 3.months.from_now)
      notify(rental)
      body = deliveries.first.html_part ? deliveries.first.html_part.body.decoded : deliveries.first.body.decoded
      expect(body).not_to include("from locker")
      expect(body).to include("now active until")
    end

    it "sends nothing for a cancelled rental's note edit or an await_payment date change" do
      cancelled = create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }
      cancelled.update!(notes: "x")
      notify(cancelled)
      awaiting = create(:locker_rental, :await_payment)
      awaiting.update!(owned_until: 3.months.from_now)
      notify(awaiting)
      expect(deliveries).to be_empty
    end

    it "returns the built mails without sending them" do
      rental = create(:locker_rental, :active)
      rental.update!(notes: "x")
      expect(rental.notification_mails).to eq([])
      rental.update!(state: :cancelled)
      expect(rental.notification_mails.size).to eq(1)
      expect(deliveries).to be_empty
    end
  end

  describe "#sync_shopify_draft_order_after_commit transitions (exact Shopify calls)" do
    let(:gid) { "gid://shopify/DraftOrder/77" }
    let!(:fake) { stub_shopify_admin!.tap { |f| f.draft_id = gid } }
    let(:reports) { [] }

    before { allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] } }

    def with_draft(rental)
      rental.update_column(:shopify_draft_order_id, gid)
      rental.reload
    end

    def delete_call
      { query: a_string_including("draftOrderDelete"), variables: { input: { id: gid } } }
    end

    def fetch_call
      { query: a_string_including("getDraftOrder"), variables: { id: gid } }
    end

    it "makes no call and keeps the id for a state change that neither ends a rental nor starts a new term" do
      [
        [create(:locker_rental, locker: create(:locker), decided_by: create(:user)), :await_payment],
        [create(:locker_rental, :await_payment), :active],
        [create(:locker_rental, locker: create(:locker), decided_by: create(:user)), :active]
      ].each do |rental, target|
        with_draft(rental).update!(state: target, owned_until: 1.month.from_now)
        expect(rental.sync_shopify_draft_order_after_commit).to be(true)
        expect(rental.reload.shopify_draft_order_id).to eq(gid)
      end
      expect(fake.calls).to be_empty
      expect(reports).to be_empty
    end

    it "makes no call when the last save did not change the state, even on a cancelled rental" do
      rental = with_draft(create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) })
      rental.update!(notes: "later note")
      expect(rental.sync_shopify_draft_order_after_commit).to be(true)
      expect(fake.calls).to be_empty
    end

    it "deletes the draft once and forgets the id when a rental is cancelled from any state" do
      %i[reviewing await_payment active].each do |from|
        rental = from == :reviewing ? create(:locker_rental) : create(:locker_rental, from)
        with_draft(rental).update!(state: :cancelled, decided_by: rental.rented_by)
        fake.calls.clear
        expect(rental.sync_shopify_draft_order_after_commit).to be(true)
        expect(fake.calls).to match([delete_call])
        expect(rental.shopify_draft_order_id).to be_nil
        expect(rental.reload.shopify_draft_order_id).to be_nil
      end
    end

    it "deletes the draft and forgets the id when an active or cancelled rental starts a new term" do
      active = with_draft(create(:locker_rental, :active))
      active.update!(state: :await_payment)
      cancelled = create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }
      with_draft(cancelled).update!(state: :await_payment)
      [active, cancelled].each do |rental|
        fake.calls.clear
        expect(rental.sync_shopify_draft_order_after_commit).to be(true)
        expect(fake.calls).to match([delete_call])
        expect(rental.reload.shopify_draft_order_id).to be_nil
      end
    end

    it "for a refused delete: fetches once, and keeps a completed draft on cancel but forgets it on a new term" do
      fake.delete_user_errors = [{ "field" => "id", "message" => "locked" }]
      fake.draft_statuses[gid] = "COMPLETED"

      ended = with_draft(create(:locker_rental, :active))
      ended.update!(state: :cancelled)
      expect(ended.sync_shopify_draft_order_after_commit).to be(true)
      expect(fake.calls).to match([delete_call, fetch_call])
      expect(ended.reload.shopify_draft_order_id).to eq(gid)

      fake.calls.clear
      renewed = with_draft(create(:locker_rental, :active))
      renewed.update!(state: :await_payment)
      expect(renewed.sync_shopify_draft_order_after_commit).to be(true)
      expect(fake.calls).to match([delete_call, fetch_call])
      expect(renewed.reload.shopify_draft_order_id).to be_nil
      expect(reports).to be_empty
    end

    it "for a refused delete of a still-open draft on a new term: reports with every Shopify message, keeps the id" do
      fake.delete_user_errors = [{ "field" => "id", "message" => "locked" }, { "field" => "id", "message" => "busy" }]
      rental = with_draft(create(:locker_rental, :active))
      rental.update!(state: :await_payment)
      expect(rental.sync_shopify_draft_order_after_commit).to be(false)
      expect(rental.reload.shopify_draft_order_id).to eq(gid)
      expect(reports.size).to eq(1)
      error, opts = reports.first
      expect(error).to be_a(LockerRental::DraftOrderNotDeleted)
      expect(error.message).to eq("Shopify did not delete the open draft order #{gid}: locked, busy")
      expect(opts).to eq(handled: true, severity: :error, context: { locker_rental_id: rental.id, step: "delete_shopify_draft_order" })
    end

    it "forgets the id of a gone draft on a new term" do
      fake.delete_user_errors = [{ "field" => "id", "message" => "not found" }]
      fake.missing_ids << gid
      rental = with_draft(create(:locker_rental, :active))
      rental.update!(state: :await_payment)
      expect(rental.sync_shopify_draft_order_after_commit).to be(true)
      expect(rental.reload.shopify_draft_order_id).to be_nil
    end

    it "keeps a newer draft id stored meanwhile (the id is only forgotten if it is still the deleted one)" do
      rental = with_draft(create(:locker_rental, :active))
      rental.update!(state: :cancelled)
      described_class.where(id: rental.id).update_all(shopify_draft_order_id: "gid://shopify/DraftOrder/78")
      expect(rental.sync_shopify_draft_order_after_commit).to be(true)
      expect(rental.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/78")
    end
  end
end
