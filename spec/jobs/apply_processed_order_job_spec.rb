# frozen_string_literal: true

require "rails_helper"

# ApplyProcessedOrderJob / ShopOrderApplier: what applying a stored orders/paid order does to memberships, CC
# Money and lockers (locker specifics: locker_orders_paid_job_spec.rb). `hook` stores the payload the way the
# webhook does (ProcessedOrder.receive!) and runs the job once. Every error is retried by the job: a run that
# fails leaves the order received with its attempt counted and a retry queued.
RSpec.describe ApplyProcessedOrderJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:membership_tag) { Membership.draft_order_operating_tag }
  let(:job_order_tag) { JobOrder.draft_order_operating_tag }
  let(:cc_product_id) { 4_359_597_129_784 }
  let(:user) { create(:user, :regular_user) }
  let!(:tier) { create(:membership_tier, title_en: "1 Day Membership", title_fr: "Adhesion 1 jour", duration: 1) }

  # Each call is a distinct Shopify order unless it names an id (a replay passes the same one).
  def hook(path_params = {}, **extra)
    topic = extra.delete(:topic) || "orders/paid"
    payload = JSON.parse({ id: SecureRandom.random_number(10**15) }.merge(path_params).merge(extra).to_json)
    plan = ShopOrderApplier.plan_for(payload, topic: topic)
    @order, = ProcessedOrder.receive!(provider: "shopify", order_id: plan.id || "x#{SecureRandom.hex(4)}", topic: topic, payload: payload, name: payload["name"])
    perform(@order)
    @order.reload
  end

  # One run as the dispatcher starts it: the order is leased, and the job carries that lease as its token.
  def perform(order)
    token = (Time.current + ProcessedOrder::LEASE).floor(6)
    ProcessedOrder.where(id: order.id).update_all(leased_until: token)
    described_class.perform_now(order.id, token)
  end

  def applied_orders = ProcessedOrder.where(status: "applied")

  # The last run failed: nothing applied, the attempt counted, the error kept, the next attempt scheduled on the row
  # (the job itself neither raises nor queues a retry).
  def expect_retry(order = @order)
    expect(order.reload).to have_attributes(status: "received", attempts: 1)
    expect(order.last_error).to be_present
    expect(order.next_attempt_at).to be > Time.current + 30.seconds
    expect(enqueued_jobs.map { |j| j["job_class"] }).not_to include("ApplyProcessedOrderJob")
  end

  def membership_payload(membership_id, **extra)
    {
      tags: [membership_tag],
      line_items: [{ title: "1 Day Membership", quantity: 1 }],
      metafields: [{ namespace: "makerepo", key: "membership_db_reference", value: membership_id.to_s }]
    }.merge(extra)
  end

  def cc_payload(email:, quantity: 2, product_id: cc_product_id)
    { customer: { email: email }, line_items: [{ product_id: product_id, quantity: quantity }] }
  end

  before do
    block_external_http!
    ActionMailer::Base.deliveries.clear
    allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields).and_return(nil)
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
      allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields).and_call_original
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
    end
  end

  # Config trouble is retried by the job BEFORE any money branch applied: the locker activation, the membership
  # paid and the CC credit are all-or-nothing with respect to NotConfigured.
  describe "when Shopify is not configured mid-run (draft_order_metafields raises NotConfigured)" do
    let!(:pending) { create(:membership, user: user, membership_tier: tier, status: "pending") }
    let!(:rental) { create(:locker_rental, :await_payment) }
    let(:payload) do
      { # the locker reference is inline; the membership one needs the Shopify lookup, which cannot run
        id: 820_982_911_946_154_508,
        tags: [membership_tag, LockerRental.draft_order_operating_tag],
        draft_order_id: 42,
        line_items: [{ title: "1 Day Membership", quantity: 3, product_id: cc_product_id }],
        customer: { email: user.email },
        metafields: [{ namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s }]
      }
    end

    before do
      allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return({})
    end

    it "applies nothing (locker not activated, membership not paid, no CC money) and retries" do
      expect { hook(payload) }.not_to change { [rental.reload.state, pending.reload.status, CcMoney.count, Membership.count] }
      expect_retry
      expect(@order.last_error).to include("NotConfigured")
      expect(a_request(:any, /graphql/)).not_to have_been_made
    end

    it "is applied in full once the config is fixed (the retry)" do
      hook(payload)
      expect_retry

      stub_shopify_credentials! # the config is fixed: the fake credentials are back
      prime_shopify_context!
      stub_shopify_graphql("query NodeMetafields", { "node" => { "metafields" => { "edges" => [
        { "node" => { "namespace" => "makerepo", "key" => "membership_db_reference", "value" => pending.id.to_s } }
      ] } } })
      perform(@order)
      expect([rental.reload.state, pending.reload.status, user.cc_moneys.pluck(:cc)]).to eq(["active", "paid", [30]])
      expect(@order.reload).to have_attributes(status: "applied", last_error: nil, attempts: 2)
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
      hook(membership_payload(pending.id, id: 7001))
      expect { hook(membership_payload(pending.id, id: 7001)) }.not_to change { pending.reload.attributes }
      expect(Membership.count).to eq(1)
    end

    it "leaves a membership an admin revoked in the meantime revoked when the order is delivered again" do
      hook(membership_payload(pending.id, id: 7002))
      pending.update!(status: "revoked")
      hook(membership_payload(pending.id, id: 7002))
      expect(pending.reload.status).to eq("revoked")
    end

    it "accepts the admin_graphql_api_id spelling of an order already applied by its numeric id" do
      hook(membership_payload(pending.id, id: 7003))
      pending.update!(status: "revoked")
      hook(membership_payload(pending.id, id: nil, admin_graphql_api_id: "gid://shopify/Order/7003"))
      expect(pending.reload.status).to eq("revoked")
    end

    it "unknown membership id: 200, nothing created (and no email fallback)" do
      expect { hook(membership_payload(999_999_999, customer: { email: user.email })) }
        .not_to change(Membership, :count)
    end

    it "falls back to Shopify's draft-order metafields (stubbed) when the payload has none" do
      allow_any_instance_of(ShopOrderApplier)
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

      it "creates one membership however often the same order is delivered" do
        hook(payload.merge(id: 7004))
        expect { 2.times { hook(payload.merge(id: 7004)) } }.not_to change(Membership, :count)
        expect(user.memberships.where(status: "paid").count).to eq(1)
      end

      it "stacks the memberships of two different orders" do
        hook(payload.merge(id: 7004))
        first_end = user.memberships.where(status: "paid").order(:id).last.end_date
        hook(payload.merge(id: 7005))
        paid = user.memberships.where(status: "paid").order(:id).to_a
        expect(paid.size).to eq(2)
        expect(paid.last.start_date).to be_within(1.second).of(first_end)
      end
    end
  end

  # ------------------------------------------------------------- job orders

  describe "cc money credit" do
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

    it "credits a replayed order once" do
      hook(cc_payload(email: user.email, quantity: 2).merge(id: 7101))
      hook(cc_payload(email: user.email, quantity: 2).merge(id: 7101))
      expect(user.cc_moneys.pluck(:cc)).to eq([20])
      expect(user.reload.get_total_cc).to eq(20)
    end

    it "credits two different orders separately" do
      hook(cc_payload(email: user.email, quantity: 2).merge(id: 7101))
      hook(cc_payload(email: user.email, quantity: 2).merge(id: 7102))
      expect(user.cc_moneys.pluck(:cc)).to eq([20, 20])
    end

    it "an unknown-buyer replay creates one claimable row and sends one claim email" do
      perform_enqueued_jobs do
        hook(cc_payload(email: "buyer@example.com").merge(id: 7103))
        hook(cc_payload(email: "buyer@example.com").merge(id: 7103))
      end
      expect(CcMoney.where(linked: false).count).to eq(1)
      expect(deliveries.size).to eq(1)
    end

    it "sends no claim email for a claim that rolled back, and the retry sends it" do
      payload = cc_payload(email: "buyer@example.com").merge(id: 7104)
      allow(CcMoney).to receive(:create!).and_raise(ActiveRecord::LockWaitTimeout, "boom")
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { hook(payload) }
      expect_retry
      expect(deliveries).to be_empty
      expect(applied_orders.where(provider_ref: "7104")).to be_empty

      allow(CcMoney).to receive(:create!).and_call_original
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { hook(payload) }
      expect(CcMoney.where(linked: false).count).to eq(1)
      expect(deliveries.size).to eq(1)
    end

    it "a failure after the first branch leaves the order unapplied so the retry applies it" do
      pending = create(:membership, user: user, membership_tier: tier, status: "pending")
      payload = membership_payload(pending.id, id: 7105, customer: { email: user.email },
                                               line_items: [{ title: "1 Day Membership", product_id: cc_product_id, quantity: 1 }])
      allow(CcMoney).to receive(:create!).and_raise(ActiveRecord::LockWaitTimeout, "boom")
      hook(payload)
      expect_retry
      expect(pending.reload.status).to eq("pending")
      expect(applied_orders.count).to eq(0)

      allow(CcMoney).to receive(:create!).and_call_original
      hook(payload)
      expect([pending.reload.status, user.cc_moneys.pluck(:cc)]).to eq(["paid", [10]])
    end
  end

  # ---------------------------------------------------- orders ledger

  it "records each applied order once in the ledger (provider, order id, topic, name)" do
    order = { id: 7201, name: "#1042", customer: { email: user.email }, line_items: [{ product_id: cc_product_id, quantity: 1 }] }
    hook(order)
    hook(order)
    hook(order.merge(id: nil, admin_graphql_api_id: "gid://shopify/Order/7201"))
    expect(ProcessedOrder.all.map { |o| [o.provider, o.provider_ref, o.topic, o.order_name] })
      .to eq([["shopify", "7201", "orders/paid", "#1042"]])
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

  # ---------------------------------------------------- the inbox contract
  # An order is applied as a whole or not at all, and every error is retried: nothing is lost because the payload
  # is stored. Decisions (the order names something that does not exist) apply what can be applied and are reported.
  describe "the inbox contract" do
    let(:reports) { [] }

    before { allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] } }

    def mixed_payload(pending, **extra)
      membership_payload(pending.id, id: 7401, customer: { email: user.email },
                                     line_items: [{ title: "1 Day Membership", product_id: cc_product_id, quantity: 1 }]).merge(extra)
    end

    it "applies, marks the row applied and counts the attempt" do
      pending = create(:membership, user: user, membership_tier: tier, status: "pending")
      order = hook(mixed_payload(pending))
      expect(order).to have_attributes(status: "applied", attempts: 1, last_error: nil)
      expect(order.applied_at).to be_present
      expect([pending.reload.status, user.cc_moneys.pluck(:cc)]).to eq(["paid", [10]])
    end

    {
      "a failed membership write" => ->(spec) { spec.allow_any_instance_of(Membership).to spec.receive(:update!).and_raise(ActiveRecord::StatementInvalid, "secret-value") },
      "a failed CC write" => ->(spec) { spec.allow(CcMoney).to spec.receive(:create!).and_raise(ActiveRecord::StatementInvalid, "secret-value") },
      "a validation refusal" => ->(spec) { spec.allow_any_instance_of(Membership).to spec.receive(:update!) { |m| raise ActiveRecord::RecordInvalid, m } },
      "an unexpected error" => ->(spec) { spec.allow_any_instance_of(Membership).to spec.receive(:update!).and_raise(NoMethodError, "undefined thing") },
      "a lock timeout" => ->(spec) { spec.allow(CcMoney).to spec.receive(:create!).and_raise(ActiveRecord::LockWaitTimeout, "x") }
    }.each do |name, failure|
      it "rolls the whole order back, records the attempt and retries after #{name}" do
        pending = create(:membership, user: user, membership_tier: tier, status: "pending")
        instance_exec(self, &failure)
        order = hook(mixed_payload(pending))
        expect_retry(order)
        expect([pending.reload.status, CcMoney.count]).to eq(["pending", 0])
        expect(order.last_error).not_to include("secret-value")
        expect(reports.map { |e, _| e.class }).to eq([ApplyProcessedOrderJob::OrderApplyRetrying]) # the early warning only

        allow_any_instance_of(Membership).to receive(:update!).and_call_original
        allow(CcMoney).to receive(:create!).and_call_original
        perform(order)
        expect(order.reload).to have_attributes(status: "applied", attempts: 2, last_error: nil)
        expect([pending.reload.status, user.cc_moneys.pluck(:cc)]).to eq(["paid", [10]])
      end
    end

    it "applies a locker plus membership order atomically" do
      rental = create(:locker_rental, :await_payment)
      pending = create(:membership, user: user, membership_tier: tier, status: "pending")
      payload = membership_payload(pending.id, id: 7402).merge(
        tags: [LockerRental.draft_order_operating_tag, membership_tag],
        metafields: [
          { namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s },
          { namespace: "makerepo", key: "membership_db_reference", value: pending.id.to_s }
        ]
      )
      allow_any_instance_of(Membership).to receive(:update!).and_raise(ActiveRecord::LockWaitTimeout, "x")
      order = hook(payload)
      expect_retry(order)
      expect([rental.reload.state, LockerPayment.count]).to eq(["await_payment", 0])

      allow_any_instance_of(Membership).to receive(:update!).and_call_original
      perform(order)
      expect([rental.reload.state, LockerPayment.count, pending.reload.status, order.reload.status])
        .to eq(["active", 1, "paid", "applied"])
    end

    it "an error in the locker branch retries the whole order too" do
      rental = create(:locker_rental, :await_payment)
      pending = create(:membership, user: user, membership_tier: tier, status: "pending")
      allow_any_instance_of(LockerRental).to receive(:record_payment).and_raise(ArgumentError, "bad")
      order = hook(membership_payload(pending.id, id: 7403).merge(
                     tags: [LockerRental.draft_order_operating_tag, membership_tag],
                     metafields: [
                       { namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s },
                       { namespace: "makerepo", key: "membership_db_reference", value: pending.id.to_s }
                     ]
                   ))
      expect_retry(order)
      expect(pending.reload.status).to eq("pending")
    end

    {
      "a membership reference that names no membership" => [ShopOrderApplier::UnknownMembership, ->(_) { membership_payload(0) }],
      "a membership order whose customer is not a user" => [ShopOrderApplier::UnresolvedMembershipOrder,
                                                           ->(_) { membership_payload("", customer: { email: "nobody@example.com" }) }],
      "a membership order with no line items" => [ShopOrderApplier::UnresolvedMembershipOrder, ->(_) { { tags: [Membership.draft_order_operating_tag] } }],
      "the CC product and no customer email" => [ShopOrderApplier::UnresolvedCcOrder, ->(_) { { line_items: [{ product_id: 4_359_597_129_784, quantity: 1 }] } }]
    }.each do |name, (error_class, build)|
      it "applies and reports #{name}" do
        order = hook(instance_exec(self, &build))
        expect(order).to have_attributes(status: "applied", attempts: 1)
        expect(reports.map { |e, _| e.class }).to eq([error_class])
        expect(reports.first.last[:context]).to include(shopify_order_id: order.provider_ref)
      end
    end

    it "sends no report for an attempt that rolls back after a decision" do
      allow(CcMoney).to receive(:create!).and_raise(ActiveRecord::LockWaitTimeout, "x")
      order = hook(membership_payload(0, id: 7404, customer: { email: user.email },
                                         line_items: [{ title: "1 Day Membership", product_id: cc_product_id, quantity: 1 }]))
      expect_retry(order)
      expect(reports.map { |e, _| e.class }).to eq([ApplyProcessedOrderJob::OrderApplyRetrying]) # none of the decision reports
    end

    it "queues the claim mail only once the order has committed" do
      calls = 0
      allow(CcMoney).to receive(:create!).and_wrap_original do |original, *args|
        calls += 1
        raise ActiveRecord::LockWaitTimeout, "x" if calls == 2

        original.call(*args)
      end
      payload = { customer: { email: "buyer@example.com" }, id: 7405,
                  line_items: [{ product_id: cc_product_id, quantity: 1 }, { product_id: cc_product_id, quantity: 1 }] }
      expect { hook(payload) }.not_to have_enqueued_mail
      calls = 2
      expect { perform(@order) }.to have_enqueued_mail(MsrMailer, :send_cc_money_email).twice
    end

    it "does nothing and asks Shopify nothing for an order that is already applied" do
      pending = create(:membership, user: user, membership_tier: tier, status: "pending")
      order = hook(membership_payload(pending.id, id: 7406))
      pending.update!(status: "revoked")
      expect_any_instance_of(ShopOrderApplier).not_to receive(:draft_order_metafields)
      perform(order)
      expect([pending.reload.status, order.reload.attempts]).to eq(["revoked", 1])
    end

    it "applies an order twice run in sequence once" do
      order = hook(cc_payload(email: user.email, quantity: 3).merge(id: 7407))
      perform(order)
      expect(user.cc_moneys.pluck(:cc)).to eq([30])
    end

    describe "the metafield lookup" do
      let(:membership_order) do
        { tags: [membership_tag], line_items: [{ title: "1 Day Membership", quantity: 1 }], draft_order_id: 99,
          customer: { email: user.email } }
      end

      before { allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields).and_call_original }

      def lookup_answers(client)
        allow_any_instance_of(ShopOrderApplier).to receive(:shopify_admin_client).and_return(client)
      end

      def graphql_error(code) = double(code: 200, body: { "errors" => [{ "extensions" => { "code" => code } }] })

      def response_with(code) = ShopifyAPI::Clients::HttpResponse.new(code: code, headers: {}, body: "")

      {
        "a raised HttpResponseError" => -> { ShopifyAPI::Errors::HttpResponseError.new(response: response_with(503)) },
        "a raised MaxHttpRetriesExceededError" => -> { ShopifyAPI::Errors::MaxHttpRetriesExceededError.new(response: response_with(429)) },
        "a read timeout" => -> { Net::ReadTimeout.new },
        "an open timeout" => -> { Net::OpenTimeout.new },
        "a refused connection" => -> { Errno::ECONNREFUSED.new }
      }.each do |name, build|
        it "retries after #{name}, applying nothing" do
          client = double
          allow(client).to receive(:query) { raise instance_exec(&build) }
          lookup_answers(client)
          order = hook(membership_order.merge(id: 7410))
          expect_retry(order)
          expect(order.last_error).to include("MetafieldLookupFailed")
          expect(Membership.count).to eq(0)
        end
      end

      %w[THROTTLED INTERNAL_SERVER_ERROR].each do |code|
        it "retries after a 200 answer carrying #{code}" do
          lookup_answers(double(query: graphql_error(code)))
          expect_retry(hook(membership_order.merge(id: 7411)))
        end
      end

      [429, 500, 502, 503].each do |code|
        it "retries after an HTTP #{code} answer" do
          lookup_answers(double(query: double(code: code, body: {})))
          expect_retry(hook(membership_order.merge(id: 7412)))
        end
      end

      it "applies a lookup Shopify refused for good as an order with no reference, and reports it" do
        lookup_answers(double(query: graphql_error("ACCESS_DENIED")))
        order = hook(membership_order.merge(id: 7413))
        expect(order).to have_attributes(status: "applied", attempts: 1)
        expect(user.memberships.paid.count).to eq(1) # the email fallback ran
        error, opts = reports.find { |e, _| e.is_a?(ShopOrderApplier::MetafieldLookupRejected) }
        expect(error.message).to include("7413", "ACCESS_DENIED")
        expect(opts[:context]).to eq(shopify_order_id: "7413", codes: ["ACCESS_DENIED"])
      end

      it "looks the draft order up once for a locker and membership order with no metafields in the payload" do
        client = double
        expect(client).to receive(:query).once.and_return(double(code: 200, body: { "data" => { "node" => nil } }))
        lookup_answers(client)
        expect(hook(membership_order.merge(id: 7414, tags: [LockerRental.draft_order_operating_tag, membership_tag])).status)
          .to eq("applied")
      end
    end

    describe "a side effect that fails after the commit" do
      def cc_order(id)
        cc_payload(email: "nobody-#{id}@example.com").merge(id: id)
      end

      it "leaves the order applied and reports the order and the side effect, without personal data" do
        mail = instance_double(ActionMailer::MessageDelivery)
        allow(mail).to receive(:deliver_later).and_raise(ActiveRecord::ConnectionNotEstablished, "queue db down")
        allow(MsrMailer).to receive(:send_cc_money_email).and_return(mail)
        order = hook(cc_order(7430))
        expect(order).to have_attributes(status: "applied", attempts: 1, last_error: nil)
        expect(CcMoney.where(linked: false).count).to eq(1)
        error, opts = reports.sole
        expect(error).to be_a(ApplyProcessedOrderJob::PostCommitSideEffectFailed)
        expect(error.message).to include("7430", "cc_claim_mail", "ConnectionNotEstablished")
        expect(error.message).not_to include("queue db down")
        expect(opts[:context]).to eq(shopify_order_id: "7430", side_effect: "cc_claim_mail", error_class: "ActiveRecord::ConnectionNotEstablished")
        expect(opts[:context].to_s).not_to include("nobody-7430")
      end

      it "reports any other post-commit failure the same way instead of failing the attempt" do
        allow_any_instance_of(ShopOrderApplier).to receive(:apply).and_wrap_original do |original, *args|
          original.call(*args)
          ActiveRecord.after_all_transactions_commit { raise "late" }
        end
        order = hook(cc_order(7431))
        expect(order).to have_attributes(status: "applied", last_error: nil)
        expect(reports.sole.last[:context]).to include(shopify_order_id: "7431", side_effect: "after_commit")
      end

      it "still retries an attempt that fails before the commit" do
        allow(CcMoney).to receive(:create!).and_raise(ActiveRecord::LockWaitTimeout, "x")
        order = hook(cc_payload(email: user.email).merge(id: 7432))
        expect(order.status).to eq("received")
        expect(reports.map { |e, _| e.class }).to eq([ApplyProcessedOrderJob::OrderApplyRetrying])
      end
    end

    describe "the schedule on the row" do
      let(:pending) { create(:membership, user: user, membership_tier: tier, status: "pending") }

      it "sets the next attempt from the row's attempts: backoff(1) after the first failure, backoff(2) after the second" do
        allow_any_instance_of(Membership).to receive(:update!).and_raise(ActiveRecord::LockWaitTimeout, "x")
        order = hook(membership_payload(pending.id, id: 7420))
        expect(order.next_attempt_at).to be_within(5.seconds).of(Time.current + ProcessedOrder.backoff(1))
        perform(order)
        expect(order.reload).to have_attributes(attempts: 2)
        expect(order.next_attempt_at).to be_within(5.seconds).of(Time.current + ProcessedOrder.backoff(2))
      end

      it "marks the order failed and reports it at the 10th failure, and not before" do
        allow_any_instance_of(Membership).to receive(:update!).and_raise(ActiveRecord::LockWaitTimeout, "x")
        order = hook(membership_payload(pending.id, id: 7421))
        order.update_columns(attempts: ProcessedOrder::MAX_ATTEMPTS - 2)
        perform(order)
        expect(order.reload).to have_attributes(status: "received", attempts: ProcessedOrder::MAX_ATTEMPTS - 1)
        expect(reports.none? { |e, _| e.is_a?(ApplyProcessedOrderJob::OrderApplyFailed) }).to be(true)

        perform(order)
        expect(order.reload).to have_attributes(status: "failed", attempts: ProcessedOrder::MAX_ATTEMPTS)
        error, opts = reports.find { |e, _| e.is_a?(ApplyProcessedOrderJob::OrderApplyFailed) }
        expect(error.message).to include("7421", "10 attempts", "LockWaitTimeout")
        expect(opts[:context]).to include(shopify_order_id: "7421", attempts: 10, error_class: "ActiveRecord::LockWaitTimeout")

        perform(order) # a failed order is not run again
        expect(order.reload.attempts).to eq(10)
      end

      it "reports OrderApplyRetrying when the row's attempts become 1 and 5 only, ids and error class only" do
        allow_any_instance_of(Membership).to receive(:update!).and_raise(ActiveRecord::LockWaitTimeout, "secret-value")
        order = hook(membership_payload(pending.id, id: 7422))
        8.times { perform(order) }
        retrying = reports.select { |e, _| e.is_a?(ApplyProcessedOrderJob::OrderApplyRetrying) }
        expect(retrying.map { |_, o| o[:context][:attempts] }).to eq([1, 5])
        expect(retrying.first.last[:context]).to eq(shopify_order_id: "7422", attempts: 1, error_class: "ActiveRecord::LockWaitTimeout")
        expect(retrying.first.first.message).not_to include("secret-value")
      end

      it "never raises, even when recording the failure raises" do
        allow_any_instance_of(Membership).to receive(:update!).and_raise(ActiveRecord::LockWaitTimeout, "x")
        allow(ProcessedOrder).to receive(:own_transaction).and_raise(ActiveRecord::ConnectionNotEstablished)
        order = ProcessedOrder.receive!(provider: "shopify", order_id: 7423, topic: "orders/paid",
                                        payload: JSON.parse(membership_payload(pending.id, id: 7423).to_json)).first
        expect { perform(order) }.not_to raise_error
      end

      it "does not touch an order a concurrent run applied while this one was failing" do
        allow_any_instance_of(Membership).to receive(:update!).and_raise(ActiveRecord::LockWaitTimeout, "x")
        allow(ProcessedOrder).to receive(:record_failure!).and_wrap_original do |original, *args|
          ProcessedOrder.where(provider_ref: "7424").update_all(status: "applied") # the other run commits first
          original.call(*args)
        end
        order = hook(membership_payload(pending.id, id: 7424))
        expect(order).to have_attributes(status: "applied", attempts: 1)
      end

      it "applies a failed order again when it is re-run" do
        allow_any_instance_of(Membership).to receive(:update!).and_raise(ActiveRecord::LockWaitTimeout, "x")
        order = hook(membership_payload(pending.id, id: 7425))
        order.update!(status: "failed")
        expect(order.reload.reapply!).to be(true)
        allow_any_instance_of(Membership).to receive(:update!).and_call_original
        perform(order)
        expect([order.reload.status, pending.reload.status]).to eq(["applied", "paid"])
      end
    end
  end
end
