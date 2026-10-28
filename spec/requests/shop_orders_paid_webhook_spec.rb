# frozen_string_literal: true

require "rails_helper"

# Characterization of the NON-locker paths of the Shopify `orders_paid` webhook
# (CustomWebhooksController#orders_paid) plus the Stripe webhook endpoint:
# memberships, job orders, legacy discount-code usage and cc-money credit.
# Locker activation lives in locker_orders_paid_webhook_spec.rb.
#
# * ShopifyApp::WebhookVerification is active in the test env: every `hook` POST is
#   signed with the test secret (spec/support/shopify_webhook_helpers.rb); forged or
#   unsigned POSTs are rejected with 401 (HMAC examples below).
# * The Shopify metafield fallback (`draft_order_metafields`) is stubbed; no
#   network. The Stripe endpoint IS signed here with the configured secret.
RSpec.describe "Shopify orders_paid webhook (shop paths)", type: :request do
  let(:membership_tag) { Membership.draft_order_operating_tag }
  let(:job_order_tag) { JobOrder.draft_order_operating_tag }
  let(:cc_product_id) { 4_359_597_129_784 }
  let(:user) { create(:user, :regular_user) }
  let!(:tier) { create(:membership_tier, title_en: "1 Day Membership", title_fr: "Adhesion 1 jour", duration: 1) }

  def hook(path_params = {})
    signed_orders_paid(path_params)
  end

  def membership_payload(membership_id, **extra)
    {
      tags: [membership_tag],
      line_items: [{ title: "1 Day Membership", quantity: 1 }],
      metafields: [{ namespace: "makerepo", key: "membership_db_reference", value: membership_id.to_s }]
    }.merge(extra)
  end

  before do
    block_external_http!
    ActionMailer::Base.deliveries.clear
    allow_any_instance_of(CustomWebhooksController).to receive(:draft_order_metafields).and_return(nil)
  end

  it "answers an empty 200 to any validly signed body, even garbage" do
    hook({})
    expect(response).to have_http_status(:ok)
    expect(response.body).to be_blank
    hook(tags: "garbage", line_items: "nope")
    expect(response).to have_http_status(:ok)
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
      [pending.reload.status, rental.reload.state, rental.paid_at, CcMoney.count, Membership.count, deliveries.size]
    end

    def expect_rejected
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to be_blank
    end

    it "rejects a request with no signature header and changes no membership, CC money or locker" do
      # WART(D-S34-nil-header, new): with no X-Shopify-Hmac-Sha256 header, shopify_app's hmac_valid? runs
      # secure_compare(nil, ...) which raises, so the response is a 500 (not a 401). Still
      # fail-closed (the action never runs), but noisy: every unsigned probe is an error report.
      expect { unsigned_orders_paid(forged) }.not_to change { money_state }
      expect(response).to have_http_status(:internal_server_error)
      expect(pending.status).to eq("pending")
      expect(rental.state).to eq("await_payment")
      expect(CcMoney.count).to eq(0)
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

    it "processes a correctly signed request: membership paid, locker active, CC money credited" do
      signed_orders_paid(forged)
      expect(response).to have_http_status(:ok)
      expect(pending.reload.status).to eq("paid")
      expect(rental.reload.state).to eq("active")
      expect(user.cc_moneys.pluck(:cc)).to eq([30])
    end
  end

  it "uses the env-specific tag names (production tags are not honored in test)" do
    expect(membership_tag).to eq("makerepo_test_membership")
    expect(job_order_tag).to eq("makerepo_test_job_order")
    expect(ShopifyConcern.target_tag).to eq("makerepo_test")
  end

  # ------------------------------------------------------------ memberships

  describe "membership path" do
    let!(:pending) { create(:membership, user: user, membership_tier: tier, status: "pending") }

    it "marks the referenced pending membership paid (dates untouched)" do
      before_dates = pending.slice(:start_date, :end_date)
      hook(membership_payload(pending.id))
      expect(response).to have_http_status(:ok)
      pending.reload
      expect(pending.status).to eq("paid")
      expect(pending.slice(:start_date, :end_date)).to eq(before_dates)
      expect(Membership.count).to eq(1)
    end

    it "accepts a comma-separated tag string too" do
      hook(membership_payload(pending.id, tags: "foo, #{membership_tag}"))
      expect(pending.reload.status).to eq("paid")
    end

    it "does nothing without line_items" do
      hook(membership_payload(pending.id).except(:line_items))
      expect(pending.reload.status).to eq("pending")
    end

    it "ignores the production tag in the test env" do
      hook(membership_payload(pending.id, tags: ["makerepo_membership"]))
      expect(pending.reload.status).to eq("pending")
    end

    it "is replay-safe when a metafield id is given (second POST changes nothing)" do
      hook(membership_payload(pending.id))
      expect { hook(membership_payload(pending.id)) }.not_to change { pending.reload.attributes }
      expect(Membership.count).to eq(1)
    end

    it "RE-PAYS a membership an admin revoked in the meantime when the webhook is replayed" do
      hook(membership_payload(pending.id))
      pending.update!(status: "revoked")
      hook(membership_payload(pending.id))
      # WART(D-S25): a replayed/late orders_paid flips a revoked membership back to paid; there is no state guard on the transition
      expect(pending.reload.status).to eq("paid")
    end

    it "unknown membership id: 200, nothing created (and no email fallback)" do
      expect { hook(membership_payload(999_999_999, customer: { email: user.email })) }
        .not_to change(Membership, :count)
      expect(response).to have_http_status(:ok)
    end

    it "falls back to Shopify's draft-order metafields (stubbed) when the payload has none" do
      allow_any_instance_of(CustomWebhooksController)
        .to receive(:draft_order_metafields)
        .and_return([{ "key" => "membership_db_reference", "value" => pending.id.to_s }])
      hook(tags: [membership_tag], line_items: [{ title: "x" }], admin_graphql_api_id: "gid://shopify/Order/1")
      expect(pending.reload.status).to eq("paid")
    end

    describe "email fallback (no metafield)" do
      let(:payload) do
        { tags: [membership_tag], customer: { email: user.email }, line_items: [{ title: "1 day membership", quantity: 1 }] }
      end

      it "creates a PAID membership for the user whose email matches, tier matched case-insensitively by title" do
        expect { hook(payload) }.to change { user.memberships.where(status: "paid").count }.by(1)
        m = user.memberships.where(status: "paid").last
        expect(m.membership_tier).to eq(tier)
        expect(m.end_date).to be > Time.current
      end

      it "matches the French title as well" do
        hook(payload.merge(line_items: [{ title: "ADHESION 1 JOUR" }]))
        expect(user.memberships.where(status: "paid").last.membership_tier).to eq(tier)
      end

      it "creates one membership per matching line item and skips unknown titles" do
        expect do
          hook(payload.merge(line_items: [{ title: "1 Day Membership" }, { title: "Mystery Box" }, { title: "1 day membership" }]))
        end.to change { user.memberships.where(status: "paid").count }.by(2)
      end

      it "does nothing for an unknown email or a missing email" do
        expect { hook(payload.merge(customer: { email: "ghost@example.com" })) }.not_to change(Membership, :count)
        expect { hook(payload.except(:customer)) }.not_to change(Membership, :count)
      end

      it "DUPLICATES (and stacks) the membership on every replay" do
        hook(payload)
        first_end = user.memberships.where(status: "paid").order(:id).last.end_date
        hook(payload)
        # WART(D-S26): the email-fallback path has no idempotency key; each delivery creates another paid membership that stacks after the previous one
        paid = user.memberships.where(status: "paid").order(:id).to_a
        expect(paid.size).to eq(2) # the pending fixture row is untouched; two NEW paid rows
        expect(paid.last.start_date).to be_within(1.second).of(first_end)
        expect(paid.last.end_date).to be_within(1.second).of(first_end + 1.day)
      end
    end
  end

  # ------------------------------------------------------------- job orders

  describe "job order path" do
    # Chunk 20a: automatic job-order payment recording was removed (it never recorded a payment,
    # D-S27). Staff set "Paid" by hand; the payment-link draft orders are still created.
    it "ignores a paid job-order draft order: 200 and no status is recorded" do
      job_order = create(:job_order, user: user)
      seed_job_statuses! if respond_to?(:seed_job_statuses!)
      payload = {
        tags: [job_order_tag],
        line_items: [{ title: "Print", quantity: 1 }],
        metafields: [{ namespace: "makerepo", key: "job_order_db_reference", value: job_order.id.to_s }]
      }
      allow(Rails.logger).to receive(:info).and_call_original
      expect { hook(payload.merge(id: 9001, name: "#1042")) }.not_to change(JobOrderStatus, :count)
      expect(response).to have_http_status(:ok)
      expect(Rails.logger).to have_received(:info).with(/paid job-order draft order ignored.*id=9001.*name="#1042"/)
    end
  end

  # ------------------------------------------------------------- cc money

  describe "cc money credit" do
    def cc_payload(email:, quantity: 2, product_id: cc_product_id)
      { customer: { email: email }, line_items: [{ product_id: product_id, quantity: quantity }] }
    end

    it "credits 10 cc per unit to a known user (by exact email)" do
      expect { hook(cc_payload(email: user.email, quantity: 3)) }.to change { user.cc_moneys.count }.by(1)
      row = user.cc_moneys.last
      expect(row.cc).to eq(30)
      expect(row.linked).to be(true)
      expect(row.order_id).to be_nil
      expect(deliveries).to be_empty
    end

    it "ignores other products, missing email and empty line items" do
      expect { hook(cc_payload(email: user.email, product_id: 1)) }.not_to change(CcMoney, :count)
      expect { hook(customer: { email: "" }, line_items: [{ product_id: cc_product_id, quantity: 1 }]) }
        .not_to change(CcMoney, :count)
      expect { hook(customer: { email: user.email }, line_items: []) }.not_to change(CcMoney, :count)
    end

    it "credits one row per matching line item" do
      hook(customer: { email: user.email },
           line_items: [{ product_id: cc_product_id, quantity: 1 }, { product_id: cc_product_id, quantity: 2 }])
      expect(user.cc_moneys.pluck(:cc).sort).to eq([10, 20])
    end

    it "quantity 0 or missing credits a zero row" do
      hook(customer: { email: user.email }, line_items: [{ product_id: cc_product_id }])
      expect(user.cc_moneys.pluck(:cc)).to eq([0])
    end

    it "unknown buyer: stores an UNLINKED cc row and delivers the claim email with a signed token" do
      perform_enqueued_jobs { hook(cc_payload(email: "buyer@example.com", quantity: 2)) }
      row = CcMoney.order(:id).last
      expect([row.user_id, row.cc, row.linked]).to eq([nil, 20, false])

      expect(deliveries.size).to eq(1)
      mail = deliveries.first
      expect(mail.to).to eq(["buyer@example.com"])
      expect(mail.subject).to eq("Your CC Money order")
      token = Rails.application.message_verifier(:cc).generate(row.id)
      # The mail embeds the token as a URL query param: base64 padding ("==",
      # present for some id lengths) is percent-escaped there, so compare the
      # escaped form (identical to the raw token when there is no padding).
      expect(mail.body.encoded).to include(CGI.escape(token))
    end

    it "email lookup is case-insensitive (the users.email column is case-insensitive)" do
      expect { hook(cc_payload(email: user.email.upcase)) }.not_to change { CcMoney.where(linked: false).count }
      expect(user.cc_moneys.pluck(:cc)).to eq([20])
    end

    it "credits the user again on every replay of the same order" do
      hook(cc_payload(email: user.email, quantity: 2))
      hook(cc_payload(email: user.email, quantity: 2))
      # WART(D-S30): replayed orders_paid double-credits cc points (no order-id dedupe); each retry of a Shopify delivery mints more points
      expect(user.cc_moneys.pluck(:cc)).to eq([20, 20])
      expect(user.reload.get_total_cc).to eq(40)
    end

    it "an unknown-buyer replay sends a second claim email and mints a second claimable row" do
      perform_enqueued_jobs do
        hook(cc_payload(email: "buyer@example.com"))
        hook(cc_payload(email: "buyer@example.com"))
      end
      expect(CcMoney.where(linked: false).count).to eq(2)
      expect(deliveries.size).to eq(2)
    end
  end

  # ---------------------------------------------------- combined payloads

  it "handles membership and cc effects of one payload in the same request" do
    m = create(:membership, user: user, membership_tier: tier, status: "pending")
    hook(
      tags: [membership_tag],
      customer: { email: user.email },
      line_items: [{ title: "1 Day Membership", product_id: cc_product_id, quantity: 1 }],
      metafields: [{ namespace: "makerepo", key: "membership_db_reference", value: m.id.to_s }]
    )
    expect(m.reload.status).to eq("paid")
    expect(user.cc_moneys.pluck(:cc)).to eq([10])
  end
end

# The Stripe endpoint (StripeEvent engine). Shop checkout is cc-points/Shopify
# only: no shop code listens to Stripe, only job orders, lockers and payout
# notification mails do (the job-order/locker handlers are pinned elsewhere).
RSpec.describe "Stripe webhook endpoint (shop-relevant behavior)", type: :request do
  def stripe_post(type, object, signed: true, secret: StripeEvent.signing_secret)
    payload = { id: "evt_#{SecureRandom.hex(4)}", object: "event", type: type, data: { object: object } }.to_json
    headers = { "CONTENT_TYPE" => "application/json" }
    if signed
      ts = Time.now
      sig = Stripe::Webhook::Signature.compute_signature(ts, payload, secret)
      headers["Stripe-Signature"] = "t=#{ts.to_i},v1=#{sig}"
    end
    post "/stripe/webhooks", params: payload, headers: headers
  end

  before do
    block_external_http!
    ActionMailer::Base.deliveries.clear
  end

  it "rejects unsigned and wrongly signed events with 400 and runs no handler" do
    expect(MsrMailer).not_to receive(:send_email_for_stripe_transfer)
    stripe_post("payout.paid", { id: "po_1" }, signed: false)
    expect(response).to have_http_status(:bad_request)
    stripe_post("payout.paid", { id: "po_1" }, secret: "whsec_wrong")
    expect(response).to have_http_status(:bad_request)
  end

  it "accepts a correctly signed event nobody subscribes to with 200" do
    stripe_post("customer.created", { id: "cus_1" })
    expect(response).to have_http_status(:ok)
  end

  it "checkout.session.completed with an unrelated reference id changes nothing (no shop handler)" do
    expect { stripe_post("checkout.session.completed", { id: "cs_1", payment_status: "paid", client_reference_id: "order-77" }) }
      .not_to change { [Order.count, CcMoney.count, Membership.count] }
    expect(response).to have_http_status(:ok)
  end

  it "ignores unpaid checkout sessions" do
    stripe_post("checkout.session.completed", { id: "cs_1", payment_status: "unpaid", client_reference_id: "job-order-1" })
    expect(response).to have_http_status(:ok)
  end

  it "checkout.session.completed without client_reference_id is a handler crash (500)" do
    # WART(D-S31): the handler calls client_reference_id.include? with no nil guard, so a payment link / session without a reference id raises and Stripe retries
    stripe_post("checkout.session.completed", { id: "cs_1", payment_status: "paid" })
    expect(response).to have_http_status(:internal_server_error)
  end

  it "payout.paid retrieves the payout (stubbed) and delivers the transfer notification" do
    destination = Struct.new(:bank_name, :routing_number).new("Bank of Test", "123456789")
    payout = Struct.new(:id, :arrival_date, :amount, :destination).new("po_1", Time.utc(2026, 5, 4).to_i, 12_345, destination)
    allow(Stripe::Payout).to receive(:retrieve).with(hash_including(id: "po_1")).and_return(payout)

    perform_enqueued_jobs { stripe_post("payout.paid", { id: "po_1" }) }
    expect(response).to have_http_status(:ok)
    expect(deliveries.size).to eq(1)
    expect(deliveries.first.body.encoded).to include("po_1")
    expect(deliveries.first.body.encoded).to include("123.45")
  end
end
