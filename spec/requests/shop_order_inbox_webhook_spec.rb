# frozen_string_literal: true

require "rails_helper"

# The Shopify order webhooks are an inbox (CustomWebhooksController#orders_paid / #orders_fulfilled): the verified
# body is stored in processed_orders and ApplyProcessedOrderJob is queued; the webhook never calls Shopify and never
# touches memberships, CC Money or lockers (what applying does: apply_processed_order_job_spec.rb).
# Every POST is signed with the test secret (spec/support/shopify_webhook_helpers.rb); wrongly signed or unsigned
# POSTs are rejected with 401 (HMAC examples below).
RSpec.describe "Shopify order webhooks (inbox)", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:membership_tag) { Membership.draft_order_operating_tag }
  let(:job_order_tag) { JobOrder.draft_order_operating_tag }
  let(:cc_product_id) { 4_359_597_129_784 }
  let(:user) { create(:user, :regular_user) }
  let!(:tier) { create(:membership_tier, title_en: "1 Day Membership", title_fr: "Adhesion 1 jour", duration: 1) }

  before do
    block_external_http!
    ActionMailer::Base.deliveries.clear
  end

  def membership_order(id: 9001, **extra)
    { id: id, name: "#1042", tags: [membership_tag], line_items: [{ title: "1 Day Membership", quantity: 1 }] }.merge(extra)
  end

  def stored(ref) = ProcessedOrder.find_by!(provider: "shopify", provider_ref: ref.to_s)

  def queued_ids = enqueued_jobs.select { |j| j["job_class"] == "ApplyProcessedOrderJob" }.map { |j| j["arguments"].first }

  describe "orders/paid" do
    it "answers 200 with an empty body, stores the verified body as received and queues the job" do
      signed_orders_paid(membership_order)
      expect(response).to have_http_status(:ok)
      expect(response.body).to be_blank
      row = stored(9001)
      expect(row).to have_attributes(topic: "orders/paid", status: "received", attempts: 0, order_name: "#1042", applied_at: nil)
      expect(row.leased_until).to be_within(1.minute).of(Time.current + ProcessedOrder::LEASE)
      expect(row.payload).to include("id" => 9001, "tags" => [membership_tag])
      expect(queued_ids).to eq([row.id])
    end

    it "stores locker-only orders and CC product orders too, one inbox for every branch" do
      signed_orders_paid({ id: 9002, tags: [LockerRental.draft_order_operating_tag] })
      signed_orders_paid({ id: 9003, customer: { email: "a@example.com" }, line_items: [{ product_id: cc_product_id, quantity: 1 }] })
      expect(ProcessedOrder.order(:id).pluck(:provider_ref)).to eq(%w[9002 9003])
    end

    it "never calls Shopify and applies nothing" do
      pending = create(:membership, user: user, membership_tier: tier, status: "pending")
      expect_any_instance_of(ShopOrderApplier).not_to receive(:draft_order_metafields)
      signed_orders_paid(membership_order.merge(draft_order_id: 5, customer: { email: user.email }))
      expect([pending.reload.status, Membership.count, CcMoney.count]).to eq(["pending", 1, 0])
    end

    it "does not duplicate the row for a redelivery, and queues nothing more: the stored order's schedule owns it" do
      body = membership_order
      signed_orders_paid(body)
      signed_orders_paid(body)
      expect(ProcessedOrder.count).to eq(1)
      expect(queued_ids).to eq([stored(9001).id])
    end

    it "queues nothing for a failed order: staff re-run it" do
      signed_orders_paid(membership_order)
      stored(9001).update!(status: "failed")
      clear_enqueued_jobs
      signed_orders_paid(membership_order)
      expect(queued_ids).to be_empty
    end

    it "queues nothing for an order already applied" do
      signed_orders_paid(membership_order)
      stored(9001).update!(status: "applied")
      clear_enqueued_jobs
      signed_orders_paid(membership_order)
      expect(response).to have_http_status(:ok)
      expect(queued_ids).to be_empty
      expect(ProcessedOrder.count).to eq(1)
    end

    it "hands an order whose backoff has passed out again on a redelivery, and one still waiting nothing" do
      signed_orders_paid(membership_order)
      clear_enqueued_jobs
      stored(9001).update_columns(next_attempt_at: 1.hour.from_now, leased_until: nil) # the first run failed
      signed_orders_paid(membership_order)
      expect(queued_ids).to be_empty
      stored(9001).update_columns(next_attempt_at: 1.minute.ago, leased_until: nil)
      signed_orders_paid(membership_order)
      expect(queued_ids).to eq([stored(9001).id])
    end

    it "answers 200 when the job cannot be queued: the stored order stays due and the dispatcher picks it up" do
      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_return(false)
      signed_orders_paid(membership_order)
      expect(response).to have_http_status(:ok)
      expect(stored(9001)).to have_attributes(status: "received")
      expect(stored(9001).next_attempt_at).to be <= Time.current

      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_call_original
      DispatchDueOrdersJob.perform_now
      expect(queued_ids).to eq([stored(9001).id])
    end

    it "answers 200 when queueing raises" do
      allow(ApplyProcessedOrderJob).to receive(:perform_later).and_raise(ActiveRecord::ConnectionNotEstablished)
      signed_orders_paid(membership_order)
      expect(response).to have_http_status(:ok)
      expect(ProcessedOrder.count).to eq(1)
    end

    it "treats the numeric id and the admin_graphql_api_id spelling of one order as one" do
      signed_orders_paid(membership_order)
      signed_orders_paid(membership_order.except(:id).merge(admin_graphql_api_id: "gid://shopify/Order/9001"))
      expect(ProcessedOrder.count).to eq(1)
    end

    it "stores nothing for an order with no branch: plain merch, a job order, garbage, a body that is not an object" do
      signed_orders_paid({ id: 9010, customer: { email: user.email }, line_items: [{ product_id: 1, quantity: 1 }] })
      signed_orders_paid({ id: 9011, tags: [job_order_tag], line_items: [{ product_id: 1 }] })
      signed_orders_paid({ id: 9012, tags: "garbage", line_items: "nope" })
      signed_orders_paid({})
      body = "[1,2]"
      post orders_paid_custom_webhooks_path, params: body, headers: shopify_webhook_headers(body)
      expect(response).to have_http_status(:ok)
      expect(ProcessedOrder.count).to eq(0)
      expect(enqueued_jobs).to be_empty
    end

    it "stores nothing and reports an order with a branch but no id" do
      reports = []
      allow(Rails.error).to receive(:report) { |e, **opts| reports << [e, opts] }
      signed_orders_paid(membership_order.except(:id))
      expect(response).to have_http_status(:ok)
      expect(ProcessedOrder.count).to eq(0)
      expect(reports.map { |e, _| e.class }).to eq([CustomWebhooksController::OrderWithoutId])
    end

    it "uses the env-specific tag names (production tags are not honored in test)" do
      expect(membership_tag).to eq("makerepo_test_membership")
      expect(job_order_tag).to eq("makerepo_test_job_order")
      signed_orders_paid({ id: 9013, tags: ["makerepo_membership"], line_items: [{ title: "x" }] })
      expect(ProcessedOrder.count).to eq(0)
    end
  end

  describe "orders/fulfilled" do
    let(:fulfilled) { { id: 9020, financial_status: "pending", tags: [LockerRental.draft_order_operating_tag] } }

    it "stores a pending locker order as its own unit (ref '<id>/fulfilled') and queues the job" do
      signed_orders_fulfilled(fulfilled)
      expect(response).to have_http_status(:ok)
      expect(stored("9020/fulfilled")).to have_attributes(topic: "orders/fulfilled", status: "received")
      expect(queued_ids).to eq([stored("9020/fulfilled").id])
    end

    it "does not collide with the orders/paid unit of the same order" do
      signed_orders_fulfilled(fulfilled)
      signed_orders_paid(fulfilled.merge(financial_status: "paid"))
      expect(ProcessedOrder.order(:id).pluck(:provider_ref, :topic))
        .to eq([["9020/fulfilled", "orders/fulfilled"], ["9020", "orders/paid"]])
    end

    %w[paid refunded voided partially_paid authorized].each do |status|
      it "stores nothing for a #{status} order" do
        signed_orders_fulfilled(fulfilled.merge(financial_status: status))
        expect(response).to have_http_status(:ok)
        expect(ProcessedOrder.count).to eq(0)
      end
    end

    it "stores nothing for an order that is not locker-tagged" do
      signed_orders_fulfilled(fulfilled.merge(tags: ["other"]))
      expect(ProcessedOrder.count).to eq(0)
    end
  end

  # --------------------------------------------------------- HMAC verification
  # ShopifyApp::WebhookVerification: X-Shopify-Hmac-Sha256 must equal
  # Base64(HMAC-SHA256(ShopifyApp.configuration.secret, raw body)); otherwise 401
  # and the action never runs. One payload would grant money in every handler.

  describe "HMAC verification" do
    let!(:pending) { create(:membership, user: user, membership_tier: tier, status: "pending") }
    let!(:rental) { create(:locker_rental, :await_payment) }
    let(:forged) do
      {
        id: 820_982_911_946_154_508,
        tags: [membership_tag, LockerRental.draft_order_operating_tag],
        line_items: [{ title: "1 Day Membership", quantity: 3, product_id: cc_product_id }],
        customer: { email: user.email },
        metafields: [
          { namespace: "makerepo", key: "membership_db_reference", value: pending.id.to_s },
          { namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s }
        ]
      }
    end

    def money_state
      [pending.reload.status, rental.reload.state, rental.paid_at, CcMoney.count, Membership.count, ProcessedOrder.count, enqueued_jobs.size]
    end

    def expect_rejected
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to be_blank
    end

    it "rejects a request with no signature header and changes no membership, CC money or locker" do
      # CustomWebhooksController#require_hmac_header! answers 401 before the gem runs.
      expect { unsigned_orders_paid(forged) }.not_to change { money_state }
      expect_rejected
      expect(pending.status).to eq("pending")
      expect(rental.state).to eq("await_payment")
      expect(CcMoney.count).to eq(0)
    end

    # Production/staging with credentials.<env>.shopify.webhook absent: the secret is nil
    # (ShopifyWebhookSecret), the app boots, and every webhook is refused with 503
    # (retryable by Shopify) and reported, even one signed with the public "test_secret".
    describe "when no webhook secret is configured" do
      before { allow(ShopifyApp.configuration).to receive(:secret).and_return(nil) }

      it "refuses a request signed with the public test_secret (503) and changes nothing, every time" do
        3.times do
          expect { signed_orders_paid(forged, secret: "test_secret") }.not_to change { money_state }
          expect(response).to have_http_status(:service_unavailable)
          expect(response.body).to be_blank
        end
        expect(pending.reload.status).to eq("pending")
        expect(rental.reload.state).to eq("await_payment")
        expect(CcMoney.count).to eq(0)
      end

      it "reports (Rails.error + Airbrake) at most once per 10 minutes per process, yet refuses every request" do
        reported = []
        allow(Rails.error).to receive(:report) { |e, **opts| reported << [e, opts] }
        allow(Airbrake).to receive(:configured?).and_return(true)
        allow(Airbrake).to receive(:notify)

        travel_to(Time.zone.local(2026, 1, 1, 12, 0, 0)) do
          3.times do
            signed_orders_paid(forged, secret: "test_secret")
            expect(response).to have_http_status(:service_unavailable)
          end
          expect(reported.size).to eq(1)
          expect(reported.first.first).to be_a(ShopifyWebhookSecret::MissingSecret)
          expect(reported.first.last).to include(severity: :error)

          travel 9.minutes
          signed_orders_paid(forged, secret: "test_secret")
          expect(response).to have_http_status(:service_unavailable)
          expect(reported.size).to eq(1)

          travel 2.minutes # 11 minutes after the first report
          signed_orders_paid(forged, secret: "test_secret")
          expect(response).to have_http_status(:service_unavailable)
          expect(reported.size).to eq(2)
        end
        expect(Airbrake).to have_received(:notify).with(an_instance_of(ShopifyWebhookSecret::MissingSecret)).twice
      end

      it "also refuses an unsigned request (503) and a blank secret" do
        expect { unsigned_orders_paid(forged) }.not_to change { money_state }
        expect(response).to have_http_status(:service_unavailable)
        allow(ShopifyApp.configuration).to receive(:secret).and_return("")
        expect { signed_orders_paid(forged, secret: "") }.not_to change { money_state }
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    # Secret rotation: the gem's hmac_valid? accepts ShopifyApp.configuration.old_secret too, so the
    # missing-secret guard must not refuse when only old_secret is set.
    describe "when only old_secret is configured (rotation)" do
      before do
        allow(ShopifyApp.configuration).to receive(:secret).and_return(nil)
        allow(ShopifyApp.configuration).to receive(:old_secret).and_return("old-rotating-secret")
      end

      it "processes a request signed with old_secret" do
        expect { signed_orders_paid(forged, secret: "old-rotating-secret") }.to change { ProcessedOrder.count }.by(1)
        expect(response).to have_http_status(:ok)
      end

      it "still rejects (401) a request signed with anything else" do
        expect { signed_orders_paid(forged, secret: "test_secret") }.not_to change { money_state }
        expect_rejected
      end
    end

    it "rejects a signature made with the wrong secret (401) and changes nothing" do
      body = forged.to_json
      bad = shopify_hmac_for(body, secret: "not-the-secret")
      expect { unsigned_orders_paid(forged, hmac: bad) }.not_to change { money_state }
      expect_rejected
    end

    it "rejects a valid signature of a different body (tampered payload) and changes nothing" do
      signature_of_benign = shopify_hmac_for({ tags: [] }.to_json)
      expect { unsigned_orders_paid(forged, hmac: signature_of_benign) }.not_to change { money_state }
      expect_rejected
    end

    it "rejects a hex digest and a blank header (wrong encoding) and changes nothing" do
      body = forged.to_json
      hex = OpenSSL::HMAC.hexdigest("sha256", shopify_webhook_secret, body)
      expect { unsigned_orders_paid(forged, hmac: hex) }.not_to change { money_state }
      expect_rejected
      expect { unsigned_orders_paid(forged, hmac: "") }.not_to change { money_state }
      expect_rejected
    end

    it "uses the configured secret (ShopifyApp.configuration.secret), not a hardcoded one" do
      expect(shopify_webhook_secret).to be_present
      body = forged.to_json
      allow(ShopifyApp.configuration).to receive(:secret).and_return("rotated-secret")
      post orders_paid_custom_webhooks_path, params: body,
           headers: shopify_webhook_headers(body, secret: "test_secret")
      expect(response).to have_http_status(:unauthorized)
      post orders_paid_custom_webhooks_path, params: body,
           headers: shopify_webhook_headers(body, secret: "rotated-secret")
      expect(response).to have_http_status(:ok)
    end

    it "stores a correctly signed request and applies nothing itself" do
      signed_orders_paid(forged)
      expect(response).to have_http_status(:ok)
      expect([pending.reload.status, rental.reload.state, CcMoney.count]).to eq(["pending", "await_payment", 0])
      expect(ProcessedOrder.count).to eq(1)
    end
  end

end
