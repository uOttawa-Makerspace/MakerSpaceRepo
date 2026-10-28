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

  describe "quote total on the magic approval page (M52)" do
    %w[en fr].each do |locale|
      it "shows the exact grand total (58.50) with locale=#{locale}" do
        order = typed_quoted_order!(:user_approval)
        get user_magic_approval_job_orders_path, params: { token: order.approval_token, locale: locale }
        expect(response).to have_http_status(:ok)
        expect(page_text).to include("Total Quote: $58.50")
      end
    end
  end

  describe "price in the staff details panel of a COMPLETED order (M53)" do
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

  # WART(D-J38): CONFIRMED. The Shopify draft order is created on the first GET
  # /job_orders/pay and never refreshed. `quote` has no status guard, so staff
  # can re-quote a COMPLETED order (it goes back to USER_APPROVAL); once the
  # order is COMPLETED again the pay page shows the OLD draft order: no create,
  # delete or update call is made, the old invoice link is served, and the
  # customer pays the old amount. Fix = delete/recreate the draft in `quote`.
  describe "Shopify payment link after a re-quote (D-J38)" do
    let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/old-invoice" } }

    def shopify_ops
      shopify.calls.map { |c| c[:query][/\b(draftOrder\w+|getDraftOrder)\b/] }
    end

    it "keeps serving the first draft order (old amount) after the order is re-quoted and completed again" do
      order = make_job_order!(owner: owner, status_key: :completed)
      task = order.job_tasks.create!(title: "Task #1")
      task.build_job_task_quote(price: 29.99, service_price: 0, service_quantity: 0).save!

      get pay_job_orders_path, params: { token: order.pay_token }
      expect(response.body).to include("https://pay.example/old-invoice")
      created = shopify.calls.first[:variables][:input][:lineItems]
      expect(created.map { |l| l[:originalUnitPriceWithCurrency][:amount] }).to eq([BigDecimal("29.99"), 0])
      first_draft_id = order.reload.shopify_draft_order_id

      # staff re-quote the (COMPLETED) order at a new price: no status guard
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => "55",
                                                          job_order: { staff_comments: "" } }
      expect(status_names(order).last).to eq("Waiting for User Approval")
      expect(order.reload.total_price).to eq(BigDecimal("55"))
      order.job_order_statuses.create!(job_status: JobStatus::COMPLETED, user: staff)

      shopify.calls.clear
      get pay_job_orders_path, params: { token: order.pay_token }

      expect(response).to have_http_status(:ok)
      # WART(D-J38): same draft id, only fetches; no create/delete/update
      expect(order.reload.shopify_draft_order_id).to eq(first_draft_id)
      expect(shopify_ops.uniq).to eq(["getDraftOrder"])
      # the link served is the one fetched from the stale draft order
      expect(response.body).to include("https://pay.example/old-invoice")
      expect(page_text).to include("Total Quote: $55.00")
    end
  end
end
