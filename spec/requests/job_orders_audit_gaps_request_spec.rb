# frozen_string_literal: true

require "rails_helper"

# Spec-audit gap closers for job orders (audit mutations M21, M44, M45, M52,
# M53 and D-J38). Every example here is killed by the mutation named in its
# comment; see the commit message for the mutation results.
RSpec.describe "JobOrders audit gaps", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  def page_text
    Nokogiri::HTML(response.body).text.gsub(/[[:space:]]+/, " ")
  end

  def typed_quoted_order!(status_key)
    order = make_job_order!(owner: owner, status_key: status_key)
    add_quoted_tasks!(order)
    order.job_tasks.update_all(job_type_id: JobType.find_by!(name: "3D Print").id)
    order
  end

  # ------------------------------------------------ customer / staff-facing money

  # skip_bullet: the multi-task quote views N+1 on quote options/line items
  # (existing perf debt; CI=1 makes Bullet raise)
  describe "quote total on the magic approval page (M52)", skip_bullet: true do
    %w[en fr].each do |locale|
      it "shows the exact grand total (58.50) with locale=#{locale}" do
        order = typed_quoted_order!(:user_approval)
        get user_magic_approval_job_orders_path, params: { token: order.approval_token, locale: locale }
        expect(response).to have_http_status(:ok)
        expect(page_text).to include("Total Quote: $58.50")
      end
    end
  end

  describe "price in the staff details panel of a COMPLETED order (M53)", skip_bullet: true do
    %w[en fr].each do |locale|
      it "shows the exact total (58.50) with locale=#{locale}" do
        order = typed_quoted_order!(:completed)
        session_login!(staff)
        get job_order_path(order), params: { locale: locale }
        expect(response).to have_http_status(:ok)
        expect(page_text).to include("Price: $58.50")
      end
    end
  end

  # ------------------------------------------------ status skipping (M21)

  # Each action is only valid from ONE status; from every other status it must
  # record nothing and flash the generic update error (WART(D-J16): no reason
  # is given). Table-driven over all ten statuses.
  describe "status transitions refuse every wrong source state" do
    actions = {
      start_processing: { param: "start_processing", from: :waiting_processed },
      processed: { param: "completed", from: :being_processed },
      paid: { param: "paid", from: :completed },
      picked_up: { param: "picked_up", from: :paid }
    }

    actions.each do |action, flow|
      JobOrderSpecHelpers::JOB_STATUS_NAMES.each_key do |state|
        next if state == flow.fetch(:from)

        it "#{action} is refused from #{state}" do
          order = make_job_order!(owner: owner, status_key: state)
          order.job_tasks.create!(title: "Task #1").build_job_task_quote(price: 10).save!
          session_login!(staff)

          expect do
            patch send("job_order_#{action}_path", order), params: { flow.fetch(:param) => "true" }
          end.not_to change(JobOrderStatus, :count)

          expect(status_names(order)).to eq([JobOrderSpecHelpers::JOB_STATUS_NAMES.fetch(state)])
          expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
          expect(flash[:notice]).to be_nil
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      it "#{action} is accepted from #{flow.fetch(:from)} (control)" do
        order = make_job_order!(owner: owner, status_key: flow.fetch(:from))
        order.job_tasks.create!(title: "Task #1").build_job_task_quote(price: 10).save!
        session_login!(staff)

        expect do
          patch send("job_order_#{action}_path", order), params: { flow.fetch(:param) => "true" }
        end.to change(JobOrderStatus, :count).by(1)
        expect(flash[:alert]).to be_nil
      end
    end
  end

  # ------------------------------------------------ upload allowlists (M44, M45)

  describe "user file content-type allowlist" do
    let(:disallowed) do
      {
        "a zip archive" => -> { FilesTestHelper.zip },
        "a Windows executable" => -> { FilesTestHelper.exe },
        "a video (mp4)" => -> { FilesTestHelper.mp4 }
      }
    end

    describe "wizard step 2 (JobTask#user_files)" do
      it "rejects each disallowed type, attaches nothing and bounces back with the validation copy" do
        disallowed.each do |label, file|
          order = make_job_order!(owner: owner)
          task = order.job_tasks.create!(title: "Task #1")
          session_login!(owner)

          expect do
            patch job_order_job_task_path(order, task),
                  params: { step: "2", job_task: { user_files: [file.call] } },
                  headers: { "HTTP_REFERER" => edit_job_order_job_task_url(order, task, step: 2) }
          end.not_to change(ActiveStorage::Attachment, :count), label

          expect(task.reload.user_files).to be_empty, label
          expect(flash[:alert]).to include("User files file should be one of"), label
        end
      end

      it "still attaches an allowed type (control)" do
        order = make_job_order!(owner: owner)
        task = order.job_tasks.create!(title: "Task #1")
        session_login!(owner)
        patch job_order_job_task_path(order, task), params: { step: "2", job_task: { user_files: [FilesTestHelper.stl] } }
        expect(task.reload.user_files.count).to eq(1)
      end
    end

    describe "POST /job_orders (JobOrder#user_files)" do
      it "refuses to create an order carrying each disallowed type" do
        session_login!(owner)
        disallowed.each do |label, file|
          expect do
            post job_orders_path, params: { job_order: { user_files: [file.call] }, redirect_step: "1" }
          end.not_to change(JobOrder, :count), label
          expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_trying_to_create")), label
        end
      end
    end
  end

  # ------------------------------------------------ D-J38

  # FIXED(D-J38): a re-quote that changes the price deletes the Shopify draft order
  # (stale line items, payable old invoice) and clears the id, so the next GET /pay
  # creates a fresh draft with the new total. Fail closed: if the old draft cannot be
  # deleted (error, not configured, already paid/completed on Shopify, order PAID or
  # later) the re-quote is refused and nothing changes. A first quote (no draft) is
  # unchanged. The pay path does NOT compare draft totals (taxes make that unsafe).
  describe "Shopify payment link after a re-quote (D-J38)" do
    let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/old-invoice" } }

    def shopify_ops
      shopify.calls.map { |c| c[:query][/\b(draftOrder\w+|getDraftOrder)\b/] }
    end

    def requote!(order, task, price)
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => price.to_s,
                                                   job_order: { staff_comments: "" } }
    end

    def order_with_draft!(status_key: :completed)
      order = make_job_order!(owner: owner, status_key: status_key)
      task = order.job_tasks.create!(title: "Task #1")
      task.build_job_task_quote(price: 29.99, service_price: 0, service_quantity: 0).save!
      order.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/9001")
      [order, task]
    end

    it "deletes the old draft on re-quote so the next pay creates a new draft with the new amount" do
      order = make_job_order!(owner: owner, status_key: :completed)
      task = order.job_tasks.create!(title: "Task #1")
      task.build_job_task_quote(price: 29.99, service_price: 0, service_quantity: 0).save!

      get pay_job_orders_path, params: { token: order.pay_token }
      expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")

      shopify.calls.clear
      requote!(order, task, 55)
      expect(status_names(order).last).to eq("Waiting for User Approval")
      expect(order.reload.total_price).to eq(BigDecimal("55"))
      expect(shopify_ops).to eq(["draftOrderDelete"])
      expect(shopify.calls.first[:variables]).to eq(input: { id: "gid://shopify/DraftOrder/9001" })
      expect(order.shopify_draft_order_id).to be_nil
      order.job_order_statuses.create!(job_status: JobStatus::COMPLETED, user: staff)

      shopify.calls.clear
      shopify.draft_id = "gid://shopify/DraftOrder/9002"
      shopify.invoice_url = "https://pay.example/new-invoice"
      get pay_job_orders_path, params: { token: order.pay_token }

      expect(response).to have_http_status(:ok)
      expect(shopify_ops).to include("draftOrderCreate")
      amounts = shopify.calls.first[:variables][:input][:lineItems].map { |l| l[:originalUnitPriceWithCurrency][:amount] }
      expect(amounts).to eq([BigDecimal("55"), 0])
      expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9002")
      expect(response.body).to include("https://pay.example/new-invoice")
      expect(response.body).not_to include("old-invoice")
    end

    it "does not touch Shopify when the re-quote leaves the price unchanged" do
      order, task = order_with_draft!
      requote!(order, task, 29.99)
      expect(status_names(order).last).to eq("Waiting for User Approval")
      expect(shopify.calls).to be_empty
      expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
    end

    it "replaces the draft when money moves between line items without changing the total" do
      order, task = order_with_draft!
      session_login!(staff)
      # 29.99 base before; after: 19.99 base + 10 x 1.00 parts = the same 29.99 total
      patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => "19.99",
                                                   "task_#{task.id}_service_qty" => "10",
                                                   "task_#{task.id}_service_price" => "1",
                                                   job_order: { staff_comments: "" } }
      expect(order.reload.total_price).to eq(BigDecimal("29.99"))
      expect(shopify_ops).to eq(["draftOrderDelete"])
      expect(order.shopify_draft_order_id).to be_nil
    end

    it "takes a row lock on the order before reading the status and line items" do
      order, task = order_with_draft!
      expect_any_instance_of(JobOrder).to receive(:lock!).at_least(:once).and_call_original
      requote!(order, task, 55)
      expect(shopify_ops).to eq(["draftOrderDelete"])
    end

    it "commits nothing and never touches Shopify when the save fails" do
      order, task = order_with_draft!
      statuses_before = status_names(order)
      allow_any_instance_of(JobOrder).to receive(:save).and_return(false)
      requote!(order, task, 55)

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
      expect(shopify.calls).to be_empty
      expect(order.reload.total_price).to eq(BigDecimal("29.99"))
      expect(status_names(order)).to eq(statuses_before)
      expect(order.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "does not touch Shopify on a first quote (no draft order yet)" do
      order = make_job_order!(owner: owner, status_key: :staff_approval)
      task = order.job_tasks.create!(title: "Task #1")
      requote!(order, task, 40)
      expect(status_names(order).last).to eq("Waiting for User Approval")
      expect(order.reload.total_price).to eq(BigDecimal("40"))
      expect(shopify.calls).to be_empty
      expect(order.shopify_draft_order_id).to be_nil
    end

    it "keeps the quote committed (and no dangling draft id) when the email fails after the draft was deleted" do
      order, task = order_with_draft!
      allow(JobOrderMailer).to receive(:send_job_quote).and_raise(Net::SMTPFatalError, "smtp down")

      requote!(order, task, 55)
      expect(response).to have_http_status(:internal_server_error)

      expect(shopify_ops).to eq(["draftOrderDelete"])
      order.reload
      # committed, and the id of the (deleted) draft is not restored
      expect(status_names(order).last).to eq("Waiting for User Approval")
      expect(order.total_price).to eq(BigDecimal("55"))
      expect(order.shopify_draft_order_id).to be_nil

      order.job_order_statuses.create!(job_status: JobStatus::COMPLETED, user: staff)
      shopify.calls.clear
      get pay_job_orders_path, params: { token: order.pay_token }
      expect(response).to have_http_status(:ok)
      expect(shopify_ops).to include("draftOrderCreate")
    end

    describe "pay path with a dangling draft id" do
      it "clears the id of a draft that no longer exists on Shopify and creates a fresh one" do
        order, = order_with_draft!
        shopify.draft_missing = true
        shopify.calls.clear
        # the fake keeps answering "draftOrder: null" for fetches; creation answers with the new id
        allow(shopify).to receive(:query).and_wrap_original do |m, **kw|
          shopify.draft_missing = false if kw[:query].include?("draftOrderCreate")
          m.call(**kw)
        end
        shopify.draft_id = "gid://shopify/DraftOrder/9003"

        get pay_job_orders_path, params: { token: order.pay_token }

        expect(response).to have_http_status(:ok)
        expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9003")
        expect(shopify_ops).to include("draftOrderCreate")
      end

      it "keeps the id on a transient Shopify error" do
        order, = order_with_draft!
        shopify.status = 502
        expect { get pay_job_orders_path, params: { token: order.pay_token } }.not_to raise_error
        expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
        expect(shopify_ops).not_to include("draftOrderCreate")
      end
    end

    shared_examples "a refused re-quote" do
      it "changes nothing and tells staff" do
        order, task = order_with_draft!(status_key: status_key)
        statuses_before = status_names(order)
        ActionMailer::Base.deliveries.clear
        break_shopify
        requote!(order, task, 55)

        expect(response).to redirect_to(job_order_path(order.id))
        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.requote_draft_order_failed"))
        expect(order.reload.total_price).to eq(BigDecimal("29.99"))
        expect(status_names(order)).to eq(statuses_before)
        expect(order.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    context "when Shopify answers non-200 on delete" do
      let(:status_key) { :completed }
      def break_shopify = (shopify.status = 502)
      it_behaves_like "a refused re-quote"
    end

    context "when the draft cannot be deleted (already completed/paid on Shopify: userErrors)" do
      let(:status_key) { :completed }
      def break_shopify = (shopify.delete_user_errors = [{ "field" => "id", "message" => "completed" }])
      it_behaves_like "a refused re-quote"
    end

    context "when the draft no longer exists on Shopify (delete returns no id, fetch says null)" do
      it "proceeds, clears the dead id and commits the re-quote" do
        order, task = order_with_draft!
        shopify.delete_user_errors = [{ "field" => "id", "message" => "not found" }]
        shopify.draft_missing = true
        requote!(order, task, 55)

        expect(status_names(order).last).to eq("Waiting for User Approval")
        expect(order.reload.total_price).to eq(BigDecimal("55"))
        expect(order.shopify_draft_order_id).to be_nil
      end

      it "refuses when the existence check itself fails (fail closed)" do
        order, task = order_with_draft!
        shopify.delete_user_errors = [{ "field" => "id", "message" => "x" }]
        allow(shopify).to receive(:query).and_wrap_original do |m, **kw|
          kw[:query].include?("draftOrderDelete") ? m.call(**kw) : (raise "boom")
        end
        requote!(order, task, 55)

        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.requote_draft_order_failed"))
        expect(order.reload.total_price).to eq(BigDecimal("29.99"))
        expect(order.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
      end
    end

    context "when Shopify is not configured / the session raises" do
      let(:status_key) { :completed }
      def break_shopify = allow(ShopifyAPI::Clients::Graphql::Admin).to(receive(:new).and_raise("not configured"))
      it_behaves_like "a refused re-quote"
    end

    context "when the order is already PAID" do
      let(:status_key) { :paid }
      def break_shopify = nil
      it_behaves_like "a refused re-quote"
    end
  end
end
