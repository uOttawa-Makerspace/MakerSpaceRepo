# frozen_string_literal: true

require "rails_helper"

# Where a Shopify order webhook goes, end to end: the signed delivery, the stored processed_orders row and what
# ApplyProcessedOrderJob then does with it, for each product a payment can be for (locker rental, membership, job
# order, shop order with the CC Money product), and of a cancelled order. Each example compares the whole stored row and the effects, in the
# order they happen.
RSpec.describe "Shopify order routing", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:locker_tag) { LockerRental.draft_order_operating_tag }
  let(:membership_tag) { Membership.draft_order_operating_tag }
  let(:job_order_tag) { JobOrder.draft_order_operating_tag }
  let(:cc_product_id) { 4_359_597_129_784 }
  let(:user) { create(:user, :regular_user) }
  let!(:tier) { create(:membership_tier, title_en: "1 Day Membership", title_fr: "Adhesion 1 jour", duration: 1) }
  let(:rental) { create(:locker_rental, :await_payment) }
  let(:pending_membership) { create(:membership, user: user, membership_tier: tier, status: "pending") }
  let(:remote_metafields) { nil }
  let(:now) { Time.utc(2026, 11, 15, 12) }

  before do
    block_external_http!
    ActionMailer::Base.deliveries.clear
    allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields) { remote_metafields }
    @reports = []
    allow(Rails.error).to receive(:report).and_wrap_original do |original, error, **kwargs|
      @reports << error.class.name
      original.call(error, **kwargs)
    end
  end

  around { |example| travel_to(now) { example.run } }

  def field(key, value) = { namespace: "makerepo", key: key, value: value.to_s }

  def locker_order(**extra)
    { id: 7001, name: "#7001", tags: [locker_tag], metafields: [field("locker_db_reference", rental.id)] }.merge(extra)
  end

  def membership_order(**extra)
    { id: 7002, name: "#7002", tags: [membership_tag], line_items: [{ title: "1 Day Membership", quantity: 1 }],
      metafields: [field("membership_db_reference", pending_membership.id)] }.merge(extra)
  end

  def cc_order(**extra)
    { id: 7003, name: "#7003", customer: { email: user.email },
      line_items: [{ product_id: cc_product_id, quantity: 2 }] }.merge(extra)
  end

  def both_references
    [field("locker_db_reference", rental.id), field("membership_db_reference", pending_membership.id)]
  end

  def job_order_order(**extra) = { id: 7004, name: "#7004", tags: [job_order_tag, "job_order:12"] }.merge(extra)

  def deliver(topic, body)
    perform_enqueued_jobs(only: [ApplyProcessedOrderJob, ApplicationMailer.delivery_job]) do
      case topic
      when "orders/fulfilled" then signed_orders_fulfilled(body)
      when "orders/cancelled" then signed_orders_cancelled(body)
      else signed_orders_paid(body)
      end
    end
    expect(response).to have_http_status(:ok)
  end

  # The stored rows, every column a run or a delivery sets.
  def stored_rows
    ProcessedOrder.order(:id).map do |o|
      o.attributes.slice("provider", "provider_ref", "topic", "order_name", "status", "attempts", "last_error")
       .merge("payload_id" => o.payload["id"], "applied" => o.applied_at.present?, "leased" => o.leased_until.present?)
    end
  end

  # The expected row of `ref` (overrides: topic, status, last_error).
  def row(ref, **overrides)
    id = ref.to_s.split("/").first
    expected = { "provider" => "shopify", "provider_ref" => ref.to_s, "topic" => "orders/paid",
                 "order_name" => "##{id}", "status" => "applied", "attempts" => 1, "last_error" => nil,
                 "payload_id" => id.to_i, "leased" => false }.merge(overrides.transform_keys(&:to_s))
    expected.merge("applied" => expected["status"] == "applied")
  end

  # The tables a job run writes, in order (INSERT and UPDATE statements), without the queue's own tables.
  def writes_during(&)
    tables = []
    callback = lambda do |*, payload|
      sql = payload[:sql].to_s
      # a statement with a WITH clause writes its own table last (the CTE writes first)
      targets = sql.match?(/\A\s*WITH\b/i) ? sql.scan(/(?:INSERT INTO|UPDATE)\s+"?(\w+)"?/i).flatten : []
      next unless (table = targets.last || sql.match(/\A\s*(?:INSERT INTO|UPDATE)\s+"?(\w+)"?/i)&.[](1))
      next if table.start_with?("solid_queue", "schema_migrations")

      tables << table
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
    tables.chunk_while { |a, b| a == b }.map(&:first)
  end

  describe "a paid order (orders/paid)" do
    it "locker rental: stores the order, records the payment and activates the rental" do
      deliver("orders/paid", locker_order)
      expect(stored_rows).to eq([row(7001)])
      expect(rental.reload).to be_active
      expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status)).to eq([%w[7001 applied]])
      expect(@reports).to be_empty
    end

    it "membership: stores the order and marks the referenced pending membership paid" do
      deliver("orders/paid", membership_order)
      expect(stored_rows).to eq([row(7002)])
      expect(pending_membership.reload.status).to eq("paid")
      expect(@reports).to be_empty
    end

    it "shop order with the CC product: stores the order and credits CC Money" do
      deliver("orders/paid", cc_order)
      expect(stored_rows).to eq([row(7003)])
      expect(CcMoney.where(user: user).pluck(:cc)).to eq([20])
    end

    it "job order: stores nothing and applies nothing, and logs the order for staff" do
      allow(Rails.logger).to receive(:info).and_call_original
      deliver("orders/paid", job_order_order(draft_order_id: 55))
      expect(stored_rows).to be_empty
      expect(Rails.logger).to have_received(:info)
        .with(/paid job-order draft order ignored.*id=7004.*draft_order_id=55/)
    end

    it "job order with the CC product: logs it and still credits the CC Money" do
      allow(Rails.logger).to receive(:info).and_call_original
      deliver("orders/paid", cc_order(id: 7005, name: "#7005", tags: [job_order_tag]))
      expect(stored_rows).to eq([row(7005)])
      expect(CcMoney.where(user: user).pluck(:cc)).to eq([20])
      expect(Rails.logger).to have_received(:info).with(/paid job-order draft order ignored/)
    end

    it "locker, membership and CC in one order: applies the locker, then the membership, then the CC Money" do
      body = locker_order(id: 7006, name: "#7006", tags: [locker_tag, membership_tag],
                          customer: { email: user.email },
                          line_items: [{ title: "1 Day Membership", quantity: 1 },
                                       { product_id: cc_product_id, quantity: 1 }],
                          metafields: both_references)
      rental
      pending_membership
      writes = writes_during { deliver("orders/paid", body) }
      expect(stored_rows).to eq([row(7006)])
      expect(writes.index("locker_payments")).to be < writes.index("memberships")
      expect(writes.index("memberships")).to be < writes.index("cc_moneys")
      expect(writes.last(2)).to eq(%w[cc_moneys processed_orders])
      expect([rental.reload.state, pending_membership.reload.status, CcMoney.where(user: user).sum(:cc)])
        .to eq(["active", "paid", 10])
    end
  end

  describe "a fulfilled order (orders/fulfilled)" do
    it "locker rental, cash still pending: stores its own fulfilled unit and records the payment" do
      deliver("orders/fulfilled", locker_order(financial_status: "pending"))
      expect(stored_rows).to eq([row("7001/fulfilled", topic: "orders/fulfilled")])
      expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status)).to eq([%w[7001 applied]])
    end

    it "locker rental already paid by card: stores nothing" do
      deliver("orders/fulfilled", locker_order(financial_status: "paid"))
      expect(stored_rows).to be_empty
      expect(rental.reload.state).to eq("await_payment")
    end

    it "membership, CC and job orders paid in cash: store nothing (staff record them)" do
      pending_membership
      deliver("orders/fulfilled", membership_order(financial_status: "pending"))
      deliver("orders/fulfilled", cc_order(financial_status: "pending"))
      deliver("orders/fulfilled", job_order_order(financial_status: "pending"))
      expect(stored_rows).to be_empty
      expect([pending_membership.reload.status, CcMoney.count]).to eq(["pending", 0])
    end

    it "a cash order for a locker and a membership applies only the locker" do
      body = locker_order(financial_status: "pending", tags: [locker_tag, membership_tag],
                          line_items: [{ title: "1 Day Membership", quantity: 1 }],
                          metafields: both_references)
      deliver("orders/fulfilled", body)
      expect(stored_rows).to eq([row("7001/fulfilled", topic: "orders/fulfilled")])
      expect([rental.reload.state, pending_membership.reload.status]).to eq(%w[active pending])
    end

    it "a cash order and the card payment of the same order are two stored units, and the locker is paid once" do
      deliver("orders/fulfilled", locker_order(financial_status: "pending"))
      deliver("orders/paid", locker_order)
      expect(stored_rows).to eq([row("7001/fulfilled", topic: "orders/fulfilled"), row(7001)])
      expect(LockerPayment.where(locker_rental: rental).count).to eq(1)
    end
  end

  describe "a cancelled order (orders/cancelled)" do
    def cancelled_order(**extra) = locker_order(financial_status: "voided", cancel_reason: "customer", **extra)

    # Everything a reversal could change, apart from the stored row.
    def locker_state
      [rental.reload.attributes, LockerPayment.order(:id).map(&:attributes), PaymentLedgerEntry.count,
       PaymentCheckout.order(:id).map(&:attributes)]
    end

    it "locker rental awaiting payment: stores its own cancelled unit, records it and changes nothing else" do
      body = cancelled_order
      csrf_token # the page the token comes from is fetched before the writes are counted
      before = locker_state
      writes = writes_during { deliver("orders/cancelled", body) }
      expect(stored_rows).to eq([row("7001/cancelled", topic: "orders/cancelled")])
      expect(writes).to eq(%w[processed_orders])
      expect(locker_state).to eq(before)
      expect([ActionMailer::Base.deliveries, @reports]).to eq([[], []])
    end

    it "locker rental paid in cash: records the cancellation, the payment and the rental stay as they are" do
      deliver("orders/fulfilled", locker_order(financial_status: "pending"))
      ActionMailer::Base.deliveries.clear
      before = locker_state
      deliver("orders/cancelled", cancelled_order)
      expect(stored_rows).to eq([row("7001/fulfilled", topic: "orders/fulfilled"),
                                 row("7001/cancelled", topic: "orders/cancelled")])
      expect(rental.reload).to be_active
      expect(locker_state).to eq(before)
      expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status)).to eq([%w[7001 applied]])
      expect([ActionMailer::Base.deliveries, @reports]).to eq([[], []])
    end

    it "a duplicate delivery: stored once, recorded once" do
      deliver("orders/cancelled", cancelled_order)
      deliver("orders/cancelled", cancelled_order)
      expect(stored_rows).to eq([row("7001/cancelled", topic: "orders/cancelled")])
    end

    it "never asks Shopify for the record a cancellation names" do
      expect_any_instance_of(ShopOrderApplier).not_to receive(:draft_order_metafields)
      deliver("orders/cancelled", cancelled_order(metafields: nil, draft_order_id: 3))
      expect(stored_rows).to eq([row("7001/cancelled", topic: "orders/cancelled")])
    end

    it "membership, CC and job orders: each stored and recorded, nothing applied" do
      pending_membership
      deliver("orders/cancelled", membership_order(financial_status: "voided"))
      deliver("orders/cancelled", cc_order(financial_status: "voided"))
      deliver("orders/cancelled", job_order_order(financial_status: "voided"))
      expect(stored_rows).to eq(%w[7002 7003 7004].map { |id| row("#{id}/cancelled", topic: "orders/cancelled") })
      expect([pending_membership.reload.status, CcMoney.count, ActionMailer::Base.deliveries]).to eq(["pending", 0, []])
    end

    it "a locker and a membership in one order: one recorded row, neither applied" do
      pending_membership
      body = locker_order(financial_status: "voided", tags: [locker_tag, membership_tag],
                          line_items: [{ title: "1 Day Membership", quantity: 1 }], metafields: both_references)
      deliver("orders/cancelled", body)
      expect(stored_rows).to eq([row("7001/cancelled", topic: "orders/cancelled")])
      expect([rental.reload.state, pending_membership.reload.status, LockerPayment.count]).to eq(["await_payment", "pending", 0])
    end

    it "an order that names no tracked product: stores nothing" do
      deliver("orders/cancelled", { id: 7013, name: "#7013", line_items: [{ product_id: 1, quantity: 1 }] })
      expect(stored_rows).to be_empty
    end
  end

  describe "an order with an unknown tag" do
    it "another environment's tag, an unknown product tag or no tags: stores nothing" do
      deliver("orders/paid", locker_order(id: 7010, tags: ["makerepo_locker", "makerepo_membership"]))
      deliver("orders/paid", locker_order(id: 7011, tags: ["#{Payments::ShopifyAdapter.target_tag}_widget"]))
      deliver("orders/paid", locker_order(id: 7012, tags: nil))
      deliver("orders/paid", { id: 7013, name: "#7013", line_items: [{ product_id: 1, quantity: 1 }] })
      expect(stored_rows).to be_empty
      expect(rental.reload.state).to eq("await_payment")
    end

    it "tags sent as something other than a string or a list name nothing: stores nothing" do
      [{ "a" => locker_tag }, 5, true].each_with_index do |tags, i|
        deliver("orders/paid", locker_order(id: 7020 + i, tags: tags))
      end
      expect(stored_rows).to be_empty
    end

    it "reads a comma-separated tag string with spaces" do
      deliver("orders/paid", locker_order(tags: "other, #{locker_tag} ,x"))
      expect(stored_rows).to eq([row(7001)])
      expect(rental.reload).to be_active
    end
  end

  describe "an order without the metafield that names the record" do
    it "locker rental, found by the Shopify lookup: applied" do
      allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields)
        .and_return([{ "key" => "locker_db_reference", "value" => rental.id.to_s }])
      deliver("orders/paid", locker_order(metafields: nil, draft_order_id: 3))
      expect(stored_rows).to eq([row(7001)])
      expect(rental.reload).to be_active
    end

    it "locker rental, not found by the lookup either: applied with nothing recorded, and reported" do
      deliver("orders/paid", locker_order(metafields: nil))
      expect(stored_rows).to eq([row(7001)])
      expect(rental.reload.state).to eq("await_payment")
      expect(@reports).to eq(["ShopOrderApplier::LockerOrderWithoutReference"])
    end

    it "membership, not found by the lookup: falls back to the customer's email and tier title" do
      deliver("orders/paid", { id: 7002, name: "#7002", tags: [membership_tag], customer: { email: user.email },
                               line_items: [{ title: "1 Day Membership", quantity: 1 }] })
      expect(stored_rows).to eq([row(7002)])
      expect(Membership.where(user: user).pluck(:status)).to eq(["paid"])
    end

    it "membership with no line item that names a tier: applied, nothing granted, and reported" do
      deliver("orders/paid", { id: 7002, name: "#7002", tags: [membership_tag], customer: { email: user.email },
                               line_items: ["1 Day Membership", { title: "Mystery Box" }] })
      expect(stored_rows).to eq([row(7002)])
      expect(Membership.where(user: user)).to be_empty
      expect(@reports).to eq(["ShopOrderApplier::UnresolvedMembershipOrder"])
    end

    it "a reference to a membership that is not pending: applied, refusal stored on the row and reported" do
      pending_membership.update!(status: "revoked")
      deliver("orders/paid", membership_order)
      refusal = "refused: membership #{pending_membership.id} is revoked, not pending"
      expect(stored_rows).to eq([row(7002, last_error: refusal)])
      expect(@reports).to eq(["ShopOrderApplier::MembershipNotPending"])
    end

    it "a lookup that must be retried: stored as received, the attempt and the error class kept on the row" do
      allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields)
        .and_raise(ShopifyConcern::MetafieldLookupFailed, "Shopify answered 503")
      deliver("orders/paid", locker_order(metafields: nil))
      error = "ShopifyConcern::MetafieldLookupFailed: Shopify answered 503"
      expect(stored_rows).to eq([row(7001, status: "received", last_error: error)])
      expect(rental.reload.state).to eq("await_payment")
    end

    it "a lookup Shopify refused for good: applied, the locker left unapplied, one report" do
      allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields)
        .and_raise(ShopifyConcern::MetafieldLookupRejected.new(["ACCESS_DENIED"]))
      deliver("orders/paid", locker_order(metafields: nil))
      expect(stored_rows).to eq([row(7001)])
      expect(rental.reload.state).to eq("await_payment")
      expect(@reports).to eq(["ShopOrderApplier::MetafieldLookupRejected"])
    end
  end

  describe "a duplicate delivery" do
    it "stores one row and applies the order once" do
      deliver("orders/paid", locker_order)
      deliver("orders/paid", locker_order)
      expect(stored_rows).to eq([row(7001)])
      expect(LockerPayment.where(locker_rental: rental).count).to eq(1)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "while the first delivery is still held by a run, hands out nothing more" do
      signed_orders_paid(locker_order)
      order = ProcessedOrder.find_by!(provider_ref: "7001")
      token = order.leased_until
      clear_enqueued_jobs
      signed_orders_paid(locker_order)
      expect(enqueued_jobs).to be_empty
      expect(order.reload.leased_until).to eq(token)

      ApplyProcessedOrderJob.perform_now(order.id, token)
      ApplyProcessedOrderJob.perform_now(order.id, token) # a duplicate job carrying the same token
      expect(stored_rows).to eq([row(7001)])
      expect(LockerPayment.where(locker_rental: rental).count).to eq(1)
    end

    it "a delivery without an order id: stores nothing and is reported" do
      deliver("orders/paid", locker_order(id: nil))
      expect(stored_rows).to be_empty
      expect(@reports).to eq(["CustomWebhooksController::OrderWithoutId"])
    end

    it "a body that is not a JSON object: stores nothing" do
      body = [locker_order].to_json
      post orders_paid_custom_webhooks_path, params: body, headers: shopify_webhook_headers(body)
      expect(response).to have_http_status(:ok)
      expect(stored_rows).to be_empty
    end
  end
end
