# frozen_string_literal: true

require "rails_helper"

# JOB-03: /pay never serves a Shopify draft whose line items no longer match the
# order (a fingerprint is stored with the draft id). A legacy draft (stored
# before fingerprints existed) is replaced once from the current line items.
RSpec.describe "Job order pay link fingerprint (JOB-03)", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/old-invoice" } }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status.name }
  end

  def shopify_ops
    shopify.calls.map { |c| c[:query][/\b(draftOrder\w+|getDraftOrder)\b/] }
  end

  def requote_mails
    ActiveJob::Base.queue_adapter.enqueued_jobs
                   .select { |j| j[:job] == ActionMailer::MailDeliveryJob && j[:args].first(2) == %w[JobOrderMailer send_job_requote_needed] }
                   .map { |j| j[:args].last["args"].first }
  end

  def quoted_order!(status_key, price: 29.99)
    order = make_job_order!(owner: owner, status_key: status_key)
    task = order.job_tasks.create!(title: "Task #1")
    task.build_job_task_quote(price: price, service_price: 0, service_quantity: 0).save!
    [order.reload, task]
  end

  # ------------------------------------------------------------------ JOB-03

  describe "GET /pay against the stored invoice fingerprint (JOB-03)" do
    def pay!(order)
      get pay_job_orders_path, params: { token: order.pay_token }
    end

    # The first /pay of an example must have created and stored a fingerprinted draft; asserting it here makes a
    # later failure name the request that went wrong.
    def pay_creates_draft!(order)
      pay!(order)
      expect(response).to have_http_status(:ok)
      expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
      expect(order.shopify_draft_order_fingerprint).to be_present
    end

    it "stores a fingerprint with the draft and serves that draft while the line items match" do
      order, = quoted_order!(:completed)
      pay!(order)
      expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
      expect(order.shopify_draft_order_fingerprint).to be_present

      shopify.calls.clear
      pay!(order)
      expect(response.body).to include("https://pay.example/old-invoice")
      expect(shopify_ops).to eq(["getDraftOrder"])
    end

    it "never serves a draft whose line items changed; the order goes back to staff and the draft is voided" do
      order, task = quoted_order!(:completed)
      pay_creates_draft!(order)
      # a price change that bypassed the quote (console, a path not yet routed through the rule)
      task.job_task_quote.update_column(:price, 5)
      shopify.calls.clear

      pay!(order)

      expect(response).to redirect_to(job_order_path(order.id))
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.pay_quote_changed"))
      expect(shopify_ops).to include("draftOrderDelete")
      expect(shopify_ops).not_to include("draftOrderCreate")
      order.reload
      expect(order.shopify_draft_order_id).to be_nil
      last = order.job_order_statuses.order(:id).last
      expect(last).to have_attributes(job_status: JobStatus::STAFF_APPROVAL, user: owner, reason: "invoice_mismatch")
      expect(requote_mails).to eq([order.id])
    end

    it "serves nothing and changes nothing when the mismatched draft cannot be deleted" do
      order, task = quoted_order!(:completed)
      pay_creates_draft!(order)
      task.job_task_quote.update_column(:price, 5)
      shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete a completed draft order" }]
      before = status_names(order)

      pay!(order)

      expect(response.body).not_to include("old-invoice")
      expect(Nokogiri::HTML(response.body).text).to include(I18n.t("job_orders.alerts.payment_link_unavailable"))
      expect(status_names(order)).to eq(before)
      expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
      expect(requote_mails).to be_empty
    end

    it "lets staff clear a mismatch with a same-price re-quote: the stale draft is replaced, not kept" do
      order, task = quoted_order!(:completed)
      pay!(order)
      task.job_task_quote.update_column(:price, 5) # changed behind the draft
      pay!(order)                                  # sent back to staff, draft voided
      # the draft is voided by the send-back; model one that survived (e.g. Shopify kept it) to pin the re-quote rule
      order.update_columns(shopify_draft_order_id: "gid://shopify/DraftOrder/9001",
                           shopify_draft_order_fingerprint: "stale-fingerprint")
      shopify.calls.clear

      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => "5",
                                                   job_order: { staff_comments: "" } }

      expect(status_names(order).last).to eq("Waiting for User Approval")
      expect(shopify_ops).to eq(["draftOrderDelete"])
      expect(order.reload.shopify_draft_order_id).to be_nil
    end

    describe "a legacy draft (stored before fingerprints existed)" do
      def legacy_order!
        order, = quoted_order!(:completed, price: 42)
        order.update_columns(shopify_draft_order_id: "gid://shopify/DraftOrder/7000",
                             shopify_draft_order_fingerprint: nil)
        shopify.draft_id = "gid://shopify/DraftOrder/7000"
        order
      end

      it "is replaced once by a draft built from the current line items, which is then served" do
        order = legacy_order!
        created = []
        allow(shopify).to receive(:query).and_wrap_original do |m, **kw|
          if kw[:query].include?("draftOrderCreate")
            created << kw[:variables][:input][:lineItems].map { |l| l[:originalUnitPriceWithCurrency][:amount] }
            shopify.draft_id = "gid://shopify/DraftOrder/7001"
            shopify.invoice_url = "https://pay.example/new-invoice"
          end
          m.call(**kw)
        end

        pay!(order)

        expect(response).to have_http_status(:ok)
        expect(shopify_ops).to include("draftOrderDelete", "draftOrderCreate")
        expect(created).to eq([[BigDecimal("42"), 0]])
        expect(response.body).to include("https://pay.example/new-invoice")
        expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/7001")
        expect(order.shopify_draft_order_fingerprint).to be_present
        expect(status_names(order).last).to eq("Completed (Waiting for Payment)")

        shopify.calls.clear
        pay!(order)
        expect(shopify_ops).to eq(["getDraftOrder"])
      end

      it "shows the try-again message and keeps the id when the legacy draft cannot be deleted" do
        order = legacy_order!
        shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete a completed draft order" }]

        pay!(order)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("old-invoice")
        expect(Nokogiri::HTML(response.body).text).to include(I18n.t("job_orders.alerts.payment_link_unavailable"))
        expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/7000")
        expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
      end
    end

    it "creates no draft when the order left COMPLETED before the lock was taken" do
      order, = quoted_order!(:completed)
      allow_any_instance_of(JobOrder).to receive(:with_lock).and_wrap_original do |m, *args, &blk|
        # an owner change sends the order back to staff just before /pay locks it
        unless JobOrderStatus.exists?(job_order_id: order.id, reason: "owner_change")
          JobOrderStatus.create!(job_order_id: order.id, job_status: JobStatus::STAFF_APPROVAL, user: owner,
                                 reason: "owner_change")
        end
        m.call(*args, &blk)
      end

      pay!(order)

      expect(shopify_ops).not_to include("draftOrderCreate")
      expect(order.reload.shopify_draft_order_id).to be_nil
      expect(response.body).not_to include("old-invoice")
    end
  end
end
