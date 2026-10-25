# frozen_string_literal: true

require "rails_helper"

# Characterization of the NON-locker paths of the Shopify `orders_paid` webhook
# (CustomWebhooksController#orders_paid) plus the Stripe webhook endpoint:
# memberships, job orders, legacy discount-code usage and cc-money credit.
# Locker activation lives in locker_orders_paid_webhook_spec.rb.
#
# * ShopifyApp::WebhookVerification is only included outside test/development,
#   so these POSTs are unsigned and still accepted (D-S24).
# * The Shopify metafield fallback (`draft_order_metafields`) is stubbed; no
#   network. The Stripe endpoint IS signed here with the configured secret.
RSpec.describe "Shopify orders_paid webhook (shop paths)", type: :request do
  let(:membership_tag) { Membership.draft_order_operating_tag }
  let(:job_order_tag) { JobOrder.draft_order_operating_tag }
  let(:cc_product_id) { 4_359_597_129_784 }
  let(:user) { create(:user, :regular_user) }
  let!(:tier) { create(:membership_tier, title_en: "1 Day Membership", title_fr: "Adhesion 1 jour", duration: 1) }

  def hook(path_params = {})
    post orders_paid_custom_webhooks_path, params: path_params, as: :json
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

  it "needs no authentication or signature in the test env and answers an empty 200 to anything" do
    # WART(D-S24): ShopifyApp::WebhookVerification is included only outside test/development (an env switch, not a security control), so HMAC verification cannot be characterized here and any non-production environment accepts forged orders_paid calls
    hook({})
    expect(response).to have_http_status(:ok)
    expect(response.body).to be_blank
    hook(tags: "garbage", line_items: "nope")
    expect(response).to have_http_status(:ok)
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
    let(:job_order) { create(:job_order, user: user) }
    let(:payload) do
      {
        tags: [job_order_tag],
        line_items: [{ title: "Print", quantity: 1 }],
        metafields: [{ namespace: "makerepo", key: "job_order_db_reference", value: job_order.id.to_s }]
      }
    end

    it "does nothing without line_items or for an unknown / missing reference" do
      hook(payload.except(:line_items))
      expect(response).to have_http_status(:ok)
      hook(payload.merge(metafields: [{ namespace: "makerepo", key: "job_order_db_reference", value: "999999999" }]))
      expect(response).to have_http_status(:ok)
      hook(payload.except(:metafields))
      expect(response).to have_http_status(:ok)
    end

    it "500s for a real job order and records no PAID status" do
      seed_job_statuses! if respond_to?(:seed_job_statuses!)
      # WART(D-S27): the hook calls JobOrder#update_status, which does not exist (the method is a private JobOrdersController helper), so a paid Shopify job-order payment raises NoMethodError and is never recorded; Shopify will retry the webhook forever
      expect { hook(payload) }.not_to change(JobOrderStatus, :count)
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  # ---------------------------------------------------------- discount codes

  describe "discount code usage" do
    let!(:code) { create(:discount_code, usage_count: 0) }

    it "bumps usage_count of the FIRST discount code that matches a stored code" do
      other_code = create(:discount_code, usage_count: 0)
      hook(discount_codes: [{ code: code.code }, { code: other_code.code }])
      expect(code.reload.usage_count).to eq(1)
      expect(other_code.reload.usage_count).to eq(0)
    end

    it "treats a NULL usage_count as zero" do
      code.update_column(:usage_count, nil)
      hook(discount_codes: [{ code: code.code }])
      expect(code.reload.usage_count).to eq(1)
    end

    it "ignores unknown codes, and never touches CouponCode (the codes users actually buy now)" do
      coupon = create(:coupon_code, :claimed, user: user)
      expect { hook(discount_codes: [{ code: coupon.code }]) }.not_to change { coupon.reload.attributes }
      expect(response).to have_http_status(:ok)
      # WART(D-S28): coupons bought with cc (CouponCode) have no usage tracking; only the retired DiscountCode rows are ever counted
    end

    it "counts the same order twice when the webhook is replayed" do
      hook(discount_codes: [{ code: code.code }])
      hook(discount_codes: [{ code: code.code }])
      # WART(D-S29): replayed orders_paid double-counts discount usage (no order-id dedupe)
      expect(code.reload.usage_count).to eq(2)
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
      expect(mail.body.encoded).to include(token)
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

  it "handles membership, discount and cc effects of one payload in the same request" do
    m = create(:membership, user: user, membership_tier: tier, status: "pending")
    code = create(:discount_code, usage_count: 0)
    hook(
      tags: [membership_tag],
      customer: { email: user.email },
      line_items: [{ title: "1 Day Membership", product_id: cc_product_id, quantity: 1 }],
      discount_codes: [{ code: code.code }],
      metafields: [{ namespace: "makerepo", key: "membership_db_reference", value: m.id.to_s }]
    )
    expect(m.reload.status).to eq("paid")
    expect(code.reload.usage_count).to eq(1)
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
