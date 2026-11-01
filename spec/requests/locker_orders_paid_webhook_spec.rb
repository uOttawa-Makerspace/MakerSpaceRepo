# frozen_string_literal: true

require "rails_helper"

# Characterization of the Shopify `orders_paid` webhook locker path
# (CustomWebhooksController#process_locker_hook -> LockerRental#record_payment).
# Every POST is signed with the test secret (see spec/support/shopify_webhook_helpers.rb);
# unsigned/forged ones are rejected, see the HMAC examples below. No network: payloads carry the metafield inline; the Shopify
# fallback lookup (`draft_order_metafields`) is stubbed.
RSpec.describe "Shopify orders_paid webhook (locker path)", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ApplicationHelper

  let(:tag) { LockerRental.draft_order_operating_tag }

  # Shopify sends the numeric order "id" on every orders/paid delivery (it is the idempotency key of the
  # payment record). UNCONFIRMED against a real staging payload: confirm before shipping.
  def payload(rental_id, tags: [tag], id: 820_982_911_946_154_508, **extra)
    {
      id: id,
      tags: tags,
      metafields: [
        { namespace: "makerepo", key: "locker_db_reference", value: rental_id.to_s }
      ]
    }.merge(extra)
  end

  before do
    ActionMailer::Base.deliveries.clear
    allow_any_instance_of(CustomWebhooksController)
      .to receive(:draft_order_metafields).and_return(nil)
  end

  it "activates an await_payment rental: defaulted owned_until, paid_at, assigned mail delivered" do
    rental = create(:locker_rental, :await_payment)
    rental.update_column(:owned_until, nil)
    ActionMailer::Base.deliveries.clear

    freeze = Time.utc(2026, 10, 20, 12)
    travel_to(freeze) do
      perform_enqueued_jobs { signed_orders_paid(payload(rental.id)) }
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_blank
    rental.reload
    expect(rental.state).to eq("active")
    expect(rental.owned_until.utc.iso8601(6)).to eq("2026-12-31T23:59:59.999999Z")
    expect(rental.paid_at).to eq(freeze)
    # WART(D-L03): the webhook activation does not set decided_by
    expect(rental.decided_by).to be_present # factory's, untouched

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    mail = ActionMailer::Base.deliveries.first
    expect(mail.to).to eq([rental.rented_by.email])
    expect(mail.subject).to eq("Locker #{rental.locker.specifier} has been assigned for you")
  end

  it "keeps a pre-set owned_until" do
    rental = create(:locker_rental, :await_payment, owned_until: 20.days.from_now)
    owned = rental.owned_until
    signed_orders_paid(payload(rental.id))
    expect(rental.reload.owned_until).to be_within(1.second).of(owned)
    expect(rental.state).to eq("active")
  end

  it "is replay-safe: a second delivery of the same order is a no-op (one payment row, no mail, paid_at kept, no report)" do
    rental = create(:locker_rental, :await_payment)
    perform_enqueued_jobs { signed_orders_paid(payload(rental.id, processed_at: "2026-10-20T12:00:00Z", total_price: "25.00", currency: "CAD", line_items: [{ title: "TEST locker on #{Rails.env} environment.", price: "20.00", quantity: 1 }, { title: "1 Day Membership", price: "5.00", quantity: 1 }])) }
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    # the LOCKER line (20.00), not the order total (25.00, which includes a membership)
    expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status, :amount, :order_total, :currency))
      .to eq([["820982911946154508", "applied", BigDecimal("20.0"), BigDecimal("25.0"), "CAD"]])

    ActionMailer::Base.deliveries.clear
    first_paid = rental.reload.paid_at
    expect(first_paid).to eq(Time.utc(2026, 10, 20, 12))
    expect(Rails.error).not_to receive(:report)
    travel_to(1.hour.from_now) do
      perform_enqueued_jobs { signed_orders_paid(payload(rental.id, processed_at: "2026-10-20T13:00:00Z")) }
    end
    expect(response).to have_http_status(:ok)
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(rental.reload.state).to eq("active")
    expect(rental.paid_at).to eq(first_paid)
    expect(LockerPayment.count).to eq(1)
  end

  it "records a different order for the same rental as a second payment row" do
    rental = create(:locker_rental, :await_payment)
    signed_orders_paid(payload(rental.id, id: 1))
    signed_orders_paid(payload(rental.id, id: 2))
    expect(rental.locker_payments.pluck(:shopify_order_id)).to contain_exactly("1", "2")
  end

  it "a second order paying an already active, already paid rental is held as already_paid (refund the duplicate)" do
    rental = create(:locker_rental, :await_payment)
    perform_enqueued_jobs { signed_orders_paid(payload(rental.id, id: 1)) }
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    ActionMailer::Base.deliveries.clear
    reports = []
    allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] }
    perform_enqueued_jobs { signed_orders_paid(payload(rental.id, id: 2)) }
    expect(response).to have_http_status(:ok)
    expect(rental.locker_payments.order(:id).pluck(:status, :hold_reason)).to eq([["applied", nil], %w[held already_paid]])
    expect(reports.size).to eq(1)
    expect(ActionMailer::Base.deliveries).to be_empty # no second "assigned" mail
  end

  describe "amounts" do
    let(:title) { "TEST locker on #{Rails.env} environment." }

    it "stores nil locker amount (and the order total apart) when the locker line cannot be identified" do
      rental = create(:locker_rental, :await_payment)
      signed_orders_paid(payload(rental.id, total_price: "42.00", line_items: [{ title: "Something else", price: "42.00", quantity: 1 }]))
      expect(rental.locker_payments.sole).to have_attributes(amount: nil, order_total: BigDecimal("42.0"))
    end

    it "a malformed or out-of-range amount does not fail the webhook: nil is stored and it is reported (ids only)" do
      rental = create(:locker_rental, :await_payment)
      reports = []
      allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] }
      signed_orders_paid(payload(rental.id, total_price: "9" * 30, line_items: [{ title: title, price: "oops", quantity: 1 }]))
      expect(response).to have_http_status(:ok)
      payment = rental.locker_payments.sole
      expect(payment).to be_applied
      expect(payment).to have_attributes(amount: nil, order_total: nil)
      expect(reports.map { |e, _| e.class }).to eq([LockerPayment::MalformedPaymentAmount] * 2)
      # a replay of the same delivery must not report them again
      reports.clear
      signed_orders_paid(payload(rental.id, total_price: "9" * 30, line_items: [{ title: title, price: "oops", quantity: 1 }]))
      expect(response).to have_http_status(:ok)
      expect(reports).to be_empty
      expect(rental.locker_payments.count).to eq(1)
    end

    it "reports the malformed figures with ids only" do
      rental = create(:locker_rental, :await_payment)
      reports = []
      allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] }
      signed_orders_paid(payload(rental.id, total_price: "bad", line_items: [{ title: title, price: "oops", quantity: 1 }]))
      expect(reports.map { |_, o| o[:context] }.uniq).to eq([{ locker_rental_id: rental.id, shopify_order_id: payload(rental.id)[:id].to_s }])
    end
  end

  it "takes the order id from admin_graphql_api_id when the payload has no id (numeric tail, same key as id)" do
    rental = create(:locker_rental, :await_payment)
    signed_orders_paid(payload(rental.id, id: nil, admin_graphql_api_id: "gid://shopify/Order/555"))
    signed_orders_paid(payload(rental.id, id: 555))
    expect(rental.locker_payments.pluck(:shopify_order_id)).to eq(["555"])
  end

  it "skips only the locker branch, reports it with ids only, and still answers 200 when a locker order carries no order id" do
    rental = create(:locker_rental, :await_payment)
    reports = []
    allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] }
    perform_enqueued_jobs { signed_orders_paid(payload(rental.id, id: nil)) }
    expect(response).to have_http_status(:ok)
    expect(rental.reload.state).to eq("await_payment")
    expect(LockerPayment.count).to eq(0)
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(reports.size).to eq(1)
    expect(reports.first.first).to be_a(CustomWebhooksController::LockerOrderWithoutId)
    expect(reports.first.last).to include(handled: true, context: { locker_rental_id: rental.id.to_s })
  end

  it "applies the membership and CC branches of a mixed order whose locker branch has no order id" do
    member = create(:user, :regular_user)
    tier = create(:membership_tier, title_en: "1 Day Membership", title_fr: "Adhesion 1 jour", duration: 1)
    pending = create(:membership, user: member, membership_tier: tier, status: "pending")
    rental = create(:locker_rental, :await_payment)
    allow(Rails.error).to receive(:report)
    signed_orders_paid(
      payload(rental.id, id: nil, tags: [tag, Membership.draft_order_operating_tag]).merge(
        line_items: [{ title: "1 Day Membership", quantity: 2, product_id: 4_359_597_129_784 }],
        customer: { email: member.email },
        metafields: [
          { namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s },
          { namespace: "makerepo", key: "membership_db_reference", value: pending.id.to_s }
        ]
      )
    )
    expect(response).to have_http_status(:ok)
    expect(rental.reload.state).to eq("await_payment")
    expect(pending.reload.status).to eq("paid")
    expect(member.cc_moneys.pluck(:cc)).to eq([20])
  end

  it "ignores other tags (production tag in test env): nothing changes, no mail" do
    rental = create(:locker_rental, :await_payment)
    perform_enqueued_jobs do
      signed_orders_paid(payload(rental.id, tags: ["makerepo_locker"]))
    end
    expect(response).to have_http_status(:ok)
    expect(rental.reload.state).to eq("await_payment")
    expect(rental.paid_at).to be_nil
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "answers 200 and does nothing for an unknown rental id or missing metafield, reporting the unknown id (ids only)" do
    reports = []
    allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] }
    perform_enqueued_jobs do
      signed_orders_paid(payload(999_999_999, id: 4242))
      expect(response).to have_http_status(:ok)
      signed_orders_paid({ tags: [tag] })
      expect(response).to have_http_status(:ok)
    end
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(LockerPayment.count).to eq(0)
    expect(reports.map { |e, _| e.class }).to eq([CustomWebhooksController::UnknownLockerRental, CustomWebhooksController::LockerOrderWithoutReference])
    expect(reports.first.last).to include(handled: true, context: { locker_rental_id: "999999999", shopify_order_id: "4242" })
  end

  it "reports a locker-tagged paid order that names no locker rental (order id only) and still answers 200" do
    reports = []
    allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] }
    signed_orders_paid({ id: 777, tags: [tag] })
    expect(response).to have_http_status(:ok)
    expect(reports.size).to eq(1)
    expect(reports.first.first).to be_a(CustomWebhooksController::LockerOrderWithoutReference)
    expect(reports.first.last).to include(handled: true, context: { shopify_order_id: "777" })
  end

  it "does not report an order that is not locker-tagged" do
    expect(Rails.error).not_to receive(:report)
    signed_orders_paid({ id: 778, tags: ["something_else"] })
    expect(response).to have_http_status(:ok)
  end

  it "falls back to the Shopify draft-order metafields (stubbed) when the payload has none" do
    rental = create(:locker_rental, :await_payment)
    allow_any_instance_of(CustomWebhooksController)
      .to receive(:draft_order_metafields)
      .and_return([{ "key" => "locker_db_reference", "value" => rental.id.to_s }])

    perform_enqueued_jobs do
      signed_orders_paid({ tags: [tag], admin_graphql_api_id: "gid://shopify/Order/1" })
    end
    expect(rental.reload.state).to eq("active")
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "answers 200 and holds the payment (not_activatable) when the rental cannot be activated, e.g. a reviewing rental with no locker" do
    rental = create(:locker_rental, :reviewing)
    expect(Rails.error).to receive(:report).once.with(an_instance_of(LockerPayment::Held), hash_including(handled: true))
    perform_enqueued_jobs { signed_orders_paid(payload(rental.id)) }
    expect(response).to have_http_status(:ok)
    expect(rental.reload.state).to eq("reviewing")
    expect(rental.locker_payments.pluck(:status, :hold_reason)).to eq([%w[held not_activatable]])
    expect(LockerRental.with_held_payment).to contain_exactly(rental)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "holds the payment of a cancelled rental and leaves it cancelled" do
    rental = create(:locker_rental, :await_payment)
    rental.update!(state: :cancelled)
    perform_enqueued_jobs { signed_orders_paid(payload(rental.id)) }
    expect(response).to have_http_status(:ok)
    expect(rental.reload).to be_cancelled
    expect(rental.locker_payments.pluck(:status, :hold_reason)).to eq([%w[held rental_cancelled]])
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  # Real Shopify payloads carry a numeric draft_order_id and no inline metafields;
  # the controller queries Shopify for them. Only the HTTP endpoint is stubbed:
  # draft_order_metafields and the GraphQL client run for real.
  describe "draft order metafield lookup over HTTP (draft_order_metafields not stubbed)" do
    let!(:rental) { create(:locker_rental, :await_payment) }
    let!(:bystander) { create(:locker_rental, :await_payment) }

    before do
      allow_any_instance_of(CustomWebhooksController).to receive(:draft_order_metafields).and_call_original
      prime_shopify_context!
    end

    def metafields_response(*fields)
      { "node" => { "metafields" => { "edges" => fields.map { |f| { "node" => f } } } } }
    end

    it "queries DraftOrder/<draft_order_id> and activates the rental referenced by the locker_db_reference metafield" do
      seen = stub_shopify_graphql("query NodeMetafields", metafields_response(
        { "namespace" => "makerepo", "key" => "locker_db_reference", "value" => rental.id.to_s }
      ))
      perform_enqueued_jobs do
        signed_orders_paid({ tags: "x, #{tag}", draft_order_id: 424_242, admin_graphql_api_id: "gid://shopify/Order/9" })
      end

      expect(response).to have_http_status(:ok)
      expect(seen.size).to eq(1)
      expect_shopify_auth(seen.first)
      expect(seen.first[:body]["query"]).to include("query NodeMetafields($ownerId: ID!)")
      expect(seen.first[:body]["variables"]).to eq("ownerId" => "gid://shopify/DraftOrder/424242")
      expect(rental.reload.state).to eq("active")
      expect(bystander.reload.state).to eq("await_payment")
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "uses admin_graphql_api_id when there is no draft_order_id" do
      seen = stub_shopify_graphql("query NodeMetafields", metafields_response(
        { "namespace" => "makerepo", "key" => "locker_db_reference", "value" => rental.id.to_s }
      ))
      signed_orders_paid({ tags: [tag], admin_graphql_api_id: "gid://shopify/Order/9" })
      expect(seen.map { |r| r[:body]["variables"] }).to eq([{ "ownerId" => "gid://shopify/Order/9" }])
      expect(rental.reload.state).to eq("active")
      expect(bystander.reload.state).to eq("await_payment")
    end

    it "picks the locker_db_reference field among other metafields (a decoy listed first is ignored)" do
      stub_shopify_graphql("query NodeMetafields", metafields_response(
        { "namespace" => "makerepo", "key" => "membership_db_reference", "value" => bystander.id.to_s },
        { "namespace" => "makerepo", "key" => "locker_db_reference", "value" => rental.id.to_s }
      ))
      signed_orders_paid({ id: 7, tags: [tag], draft_order_id: 5 })
      expect(rental.reload.state).to eq("active")
      expect(bystander.reload.state).to eq("await_payment")
    end

    it "does nothing when Shopify returns no locker_db_reference" do
      stub_shopify_graphql("query NodeMetafields", metafields_response)
      signed_orders_paid({ tags: [tag], draft_order_id: 1 })
      expect(response).to have_http_status(:ok)
      expect(LockerRental.where(state: "active")).to be_empty
    end
  end


  # A payment for a renter who is not eligible (deactivated, soft-deleted, or both) is recorded as HELD: the
  # rental is never activated, one report is made, staff decide (refund / dismiss / assign). The webhook
  # answers 200 and still applies the order's other effects.
  describe "a paid locker whose renter is not eligible" do
    let(:cc_product_id) { 4_359_597_129_784 }
    let(:member) { create(:user, :regular_user) }
    let!(:tier) { create(:membership_tier, title_en: "1 Day Membership", title_fr: "Adhesion 1 jour", duration: 1) }
    let!(:pending) { create(:membership, user: member, membership_tier: tier, status: "pending") }
    let!(:rental) { create(:locker_rental, :await_payment, owned_until: nil) }
    let(:full_payload) do
      payload(rental.id, tags: [tag, Membership.draft_order_operating_tag]).merge(
        line_items: [{ title: "1 Day Membership", quantity: 3, product_id: cc_product_id }],
        customer: { email: member.email },
        metafields: [
          { namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s },
          { namespace: "makerepo", key: "membership_db_reference", value: pending.id.to_s }
        ]
      )
    end

    {
      "deactivated" => ->(u) { u.deactivate! },
      "soft-deleted" => ->(u) { u.update_columns(deleted: true) },
      "deactivated and soft-deleted" => ->(u) { u.deactivate!; u.update_columns(deleted: true) }
    }.each do |label, change|
      it "(#{label}) answers 200, holds the payment, does not activate, reports once, and still applies the other effects" do
        change.call(rental.rented_by)
        reports = []
        allow(Rails.error).to receive(:report).and_call_original
        allow(Rails.error).to receive(:report).with(an_instance_of(LockerPayment::Held), anything) { |e, **o| reports << [e, o] }

        perform_enqueued_jobs { signed_orders_paid(full_payload) }

        expect(response).to have_http_status(:ok)
        rental.reload
        expect(rental.state).to eq("await_payment")
        expect(rental.paid_at).to be_nil # a held payment never moves the display-only paid_at
        payment = rental.locker_payments.sole
        expect(payment).to have_attributes(status: "held", hold_reason: "renter_ineligible", resolved_at: nil)
        expect(LockerRental.with_held_payment).to contain_exactly(rental)
        expect(ActionMailer::Base.deliveries).to be_empty # no "locker assigned" mail

        expect(reports.size).to eq(1)
        expect(reports.first.last[:context]).to eq(
          locker_payment_id: payment.id, locker_rental_id: rental.id, user_id: rental.rented_by_id, hold_reason: "renter_ineligible"
        )

        expect(pending.reload.status).to eq("paid")
        expect(member.cc_moneys.pluck(:cc)).to eq([30])

        # replay: still one row, still one report
        perform_enqueued_jobs { signed_orders_paid(payload(rental.id)) }
        expect(response).to have_http_status(:ok)
        expect(rental.locker_payments.count).to eq(1)
        expect(reports.size).to eq(1)
      end
    end

    it "holds a payment for an already ACTIVE rental of a deactivated renter (state untouched, badge on the list)" do
      active = create(:locker_rental, :active)
      active.rented_by.deactivate!
      signed_orders_paid(payload(active.id))
      expect(response).to have_http_status(:ok)
      expect(active.reload).to be_active
      expect(active.locker_payments.sole).to be_held
      expect(LockerRental.with_held_payment).to contain_exactly(active)
    end

    it "holds a reviewing rental's payment too, without raising and without activating it" do
      reviewing = create(:locker_rental, :reviewing)
      reviewing.rented_by.deactivate!
      signed_orders_paid(payload(reviewing.id))
      expect(response).to have_http_status(:ok)
      expect(reviewing.reload).to have_attributes(state: "reviewing", paid_at: nil)
      expect(reviewing.locker_payments.sole).to be_held
    end

    it "stays held when the renter is reactivated or staff cancel the rental: only staff resolve it" do
      change = rental.rented_by
      change.deactivate!
      signed_orders_paid(payload(rental.id))
      change.reactivate!
      expect(LockerRental.with_held_payment).to contain_exactly(rental)
      rental.reload.update!(state: :cancelled, decided_by: create(:user, :staff))
      expect(LockerRental.with_held_payment).to contain_exactly(rental)
      expect(rental.locker_payments.sole).to be_held
    end

    it "activates normally when the renter is eligible (unchanged behaviour)" do
      other = create(:locker_rental, :await_payment)
      signed_orders_paid(payload(other.id))
      expect(other.reload.state).to eq("active")
      expect(other.locker_payments.sole).to be_applied
      expect(LockerRental.with_held_payment).to be_empty
    end
  end
end
