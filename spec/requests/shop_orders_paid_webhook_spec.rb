# frozen_string_literal: true

require "rails_helper"

# Characterization of the NON-locker paths of the Shopify `orders_paid` webhook
# (CustomWebhooksController#orders_paid):
# memberships, job orders, legacy discount-code usage and cc-money credit.
# Locker activation lives in locker_orders_paid_webhook_spec.rb.
#
# * ShopifyApp::WebhookVerification is active in the test env: every `hook` POST is
#   signed with the test secret (spec/support/shopify_webhook_helpers.rb); forged or
#   unsigned POSTs are rejected with 401 (HMAC examples below).
# * The Shopify metafield fallback (`draft_order_metafields`) is stubbed; no
#   network.
RSpec.describe "Shopify orders_paid webhook (shop paths)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

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
      # Fixed (was WART D-S34-nil-header): the gem's secure_compare(nil, ..) used to raise (500);
      # CustomWebhooksController#require_hmac_header! now answers 401 before the gem runs.
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
        expect { signed_orders_paid(forged, secret: "old-rotating-secret") }.to change { pending.reload.status }.to("paid")
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

    it "processes a correctly signed request: membership paid, locker active, CC money credited" do
      signed_orders_paid(forged)
      expect(response).to have_http_status(:ok)
      expect(pending.reload.status).to eq("paid")
      expect(rental.reload.state).to eq("active")
      expect(user.cc_moneys.pluck(:cc)).to eq([30])
    end
  end

  # ---------------------------------------------- metafield lookup over real HTTP
  # Real Shopify orders/paid payloads carry no inline `metafields` and a numeric
  # `draft_order_id`; the controller then asks Shopify (NodeMetafields query) for
  # the draft order's metafields. Only the HTTP endpoint is stubbed here;
  # `draft_order_metafields` and the GraphQL client run for real.
  describe "draft order metafield lookup (draft_order_metafields not stubbed)" do
    let!(:pending) { create(:membership, user: user, membership_tier: tier, status: "pending") }
    let!(:bystander) { create(:membership, user: create(:user, :regular_user), membership_tier: tier, status: "pending") }

    before do
      allow_any_instance_of(CustomWebhooksController).to receive(:draft_order_metafields).and_call_original
      prime_shopify_context!
    end

    def metafields_response(*fields)
      { "node" => { "metafields" => { "edges" => fields.map { |f| { "node" => f } } } } }
    end

    def membership_ref(id)
      { "namespace" => "makerepo", "key" => "membership_db_reference", "value" => id.to_s }
    end

    def real_payload(**extra)
      { tags: "foo, #{membership_tag}", line_items: [{ title: "1 Day Membership", quantity: 1 }] }.merge(extra)
    end

    it "turns a numeric draft_order_id into a DraftOrder gid, queries its metafields and marks that membership paid" do
      seen = stub_shopify_graphql("query NodeMetafields", metafields_response(
        { "namespace" => "custom", "key" => "other", "value" => "1" }, membership_ref(pending.id)
      ))
      hook(real_payload(draft_order_id: 987_654, admin_graphql_api_id: "gid://shopify/Order/555"))

      expect(response).to have_http_status(:ok)
      expect(seen.size).to eq(1)
      expect_shopify_auth(seen.first)
      expect(seen.first[:body]["query"]).to include("query NodeMetafields($ownerId: ID!)")
      expect(seen.first[:body]["variables"]).to eq("ownerId" => "gid://shopify/DraftOrder/987654")
      expect(pending.reload.status).to eq("paid")
      expect(bystander.reload.status).to eq("pending")
      expect(Membership.count).to eq(2)
    end

    it "falls back to admin_graphql_api_id as the owner id when the hook has no draft_order_id" do
      seen = stub_shopify_graphql("query NodeMetafields", metafields_response(membership_ref(pending.id)))
      hook(real_payload(admin_graphql_api_id: "gid://shopify/Order/555"))

      expect(seen.map { |r| r[:body]["variables"] }).to eq([{ "ownerId" => "gid://shopify/Order/555" }])
      expect(pending.reload.status).to eq("paid")
      expect(bystander.reload.status).to eq("pending")
    end

    it "ignores metafields that are not the membership reference: nothing is marked paid and no row is created" do
      stub_shopify_graphql("query NodeMetafields", metafields_response(
        { "namespace" => "makerepo", "key" => "locker_db_reference", "value" => pending.id.to_s }
      ))
      expect { hook(real_payload(draft_order_id: 1)) }.not_to change { Membership.pluck(:id, :status).sort }
      expect(response).to have_http_status(:ok)
    end
  end

  # Shopify retries a non-2xx webhook, so config trouble must answer 503 BEFORE any money branch applied:
  # locker activation, membership paid and CC credit are all-or-nothing with respect to NotConfigured.
  describe "when Shopify is not configured mid-webhook (draft_order_metafields raises NotConfigured)" do
    let!(:pending) { create(:membership, user: user, membership_tier: tier, status: "pending") }
    let!(:rental) { create(:locker_rental, :await_payment) }
    let(:payload) do
      { # the locker reference is inline; the membership one needs the Shopify lookup, which cannot run
        tags: [membership_tag, LockerRental.draft_order_operating_tag],
        draft_order_id: 42,
        line_items: [{ title: "1 Day Membership", quantity: 3, product_id: cc_product_id }],
        customer: { email: user.email },
        metafields: [{ namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s }]
      }
    end

    before do
      allow_any_instance_of(CustomWebhooksController).to receive(:draft_order_metafields).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return({})
      allow(Rails.logger).to receive(:warn)
    end

    it "answers 503 and has applied nothing (locker not activated, membership not paid, no CC money)" do
      expect { signed_orders_paid(payload) }.not_to change { [rental.reload.state, pending.reload.status, CcMoney.count, Membership.count] }
      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to be_blank
      expect(a_request(:any, /graphql/)).not_to have_been_made
    end

    it "is processed in full once the config is fixed (Shopify's retry)" do
      signed_orders_paid(payload)
      expect(response).to have_http_status(:service_unavailable)

      stub_shopify_credentials! # the config is fixed: the fake credentials are back
      prime_shopify_context!
      stub_shopify_graphql("query NodeMetafields", { "node" => { "metafields" => { "edges" => [
        { "node" => { "namespace" => "makerepo", "key" => "membership_db_reference", "value" => pending.id.to_s } }
      ] } } })
      signed_orders_paid(payload)
      expect(response).to have_http_status(:ok)
      expect([rental.reload.state, pending.reload.status, user.cc_moneys.pluck(:cc)]).to eq(["active", "paid", [30]])
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
