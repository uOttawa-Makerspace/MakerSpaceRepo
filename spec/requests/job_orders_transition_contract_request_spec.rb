# frozen_string_literal: true

require "rails_helper"

# Round 2 review 1-3: JobOrder#transition! has one failure contract. It always
# returns a TransitionResult; every refusal (wrong state, spent link, a draft it
# cannot void, a status row that does not validate) is a result with a reason
# and a message, nothing committed, never a 500. Callers read the result, never
# a carried-over flash.
RSpec.describe "Job order transition failure contract", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let!(:shopify) { stub_shopify_admin! }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  def quoted_order!(status_key, price: 29.99)
    order = make_job_order!(owner: owner, status_key: status_key)
    order.job_tasks.create!(title: "Task #1", job_type: JobType.find_by!(name: "3D Print"))
         .build_job_task_quote(price: price, service_price: 0, service_quantity: 0).save!
    order.reload
  end

  describe "an invalid status row is a refused result, reported, nothing committed" do
    it "nil actor" do
      order = quoted_order!(:waiting_processed)
      expect(Rails.error).to receive(:report).with(an_instance_of(ActiveRecord::RecordInvalid), hash_including(handled: true))

      result = order.transition!(from: JobStatus::WAITING_PROCESSED, to: JobStatus::BEING_PROCESSED, actor: nil)

      expect(result).not_to be_ok
      expect(result.reason).to eq(:invalid_status_row)
      expect(result.message_key).to eq("job_orders.alerts.status_change_not_recorded")
      expect(status_names(order)).to eq(["Waiting to be Processed"])
    end

    it "unseeded destination status on a staff transition: a clear message, no 500" do
      order = quoted_order!(:waiting_processed)
      stub_const("JobStatus::BEING_PROCESSED", nil)
      session_login!(staff)
      patch job_order_start_processing_path(order), params: { start_processing: "true" }

      expect(response).to redirect_to(job_order_path(order.id))
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.status_change_not_recorded"))
      expect(status_names(order)).to eq(["Waiting to be Processed"])
    end

    it "unseeded destination status on the emailed approval: no 500, nothing recorded" do
      order = quoted_order!(:user_approval)
      stub_const("JobStatus::WAITING_PROCESSED", nil)
      patch user_magic_approval_confirmation_job_orders_path, params: { token: order.approval_token, approved: "true" }

      expect(response).to have_http_status(:ok)
      expect(status_names(order)).to eq(["Waiting for User Approval"])
    end

    it "unseeded status on a quote: the quote rolls back with a clear message" do
      order = quoted_order!(:staff_approval)
      task = order.job_tasks.first
      stub_const("JobStatus::USER_APPROVAL", nil)
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => "77",
                                                   job_order: { staff_comments: "" } }

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.status_change_not_recorded"))
      expect(order.reload.total_price).to eq(BigDecimal("29.99"))
      expect(status_names(order)).to eq(["Waiting for Staff Approval"])
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "unseeded status on a decline: a clear message, no 500" do
      order = quoted_order!(:staff_approval)
      stub_const("JobStatus::DECLINED", nil)
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "false", job_order: { staff_comments: "" } }

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.status_change_not_recorded"))
      expect(status_names(order)).to eq(["Waiting for Staff Approval"])
    end
  end

  describe "the caller's message comes from the result, not from a carried-over flash" do
    def incomplete_order!
      make_job_order!(owner: owner, status_key: :staff_approval).tap do |order|
        order.job_tasks.create!(title: "Task #1") # no job type: the order page shows the missing-info alert
      end
    end

    it "a refused approval says so even right after the order page set its missing-info alert" do
      order = incomplete_order!
      session_login!(owner)
      get job_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(flash[:alert]).to start_with(I18n.t("job_orders.alerts.missing_info"))

      patch job_order_user_approval_path(order), params: { approved: "true" } # wrong state: no quote yet
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
      expect(status_names(order)).to eq(["Waiting for Staff Approval"])
    end

    it "the order page's alert is for that page only (flash.now)" do
      order = incomplete_order!
      session_login!(owner)
      get job_order_path(order)
      get job_orders_path

      expect(flash[:alert]).to be_nil
    end
  end

  describe "the $0 bypass in processed" do
    it "marks a $0 order Paid and says so" do
      order = quoted_order!(:being_processed, price: 0)
      session_login!(staff)
      patch job_order_processed_path(order), params: { completed: "true" }

      expect(status_names(order).last(2)).to eq(["Completed (Waiting for Payment)", "Paid (Waiting for Pick-Up)"])
      expect(flash[:notice]).to eq(I18n.t("job_orders.alerts.updated_job_status_to_x", status: JobStatus::PAID.t_name))
    end

    it "alerts, and shows no success notice, when the $0 order could not be marked Paid" do
      order = quoted_order!(:being_processed, price: 0)
      order.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/9001") # a draft it cannot check
      shopify.status = 502
      session_login!(staff)
      patch job_order_processed_path(order), params: { completed: "true" }

      expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.zero_order_not_marked_paid.draft_not_voidable"))
      expect(flash[:alert]).to include("is Completed").and include("could not be marked Paid")
      expect(flash[:alert]).not_to match(/nothing was changed/i)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  # Round 3 review 2, 4, 5: the failure contract is closed (every refusal is a result), the one exception report
  # lives in transition!, and a refusal undoes everything it did, also inside a caller's transaction.
  describe "refusals made from an exception" do
    def reload_free(order) = JobOrder.find(order.id)

    it "reports the Shopify error behind a draft refusal once, with the order and the statuses" do
      order = quoted_order!(:completed)
      order.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/9001")
      shopify.status = 502
      expect(Rails.error).to receive(:report)
        .with(an_instance_of(JobOrder::StaleDraftOrderError),
              handled: true, context: { job_order_id: order.id, from: ["Completed (Waiting for Payment)"],
                                        to: "Paid (Waiting for Pick-Up)" }).once
      allow(Rails.logger).to receive(:error)

      result = order.transition!(from: JobStatus::COMPLETED, to: JobStatus::PAID, actor: staff)

      expect(result.reason).to eq(:draft_not_voidable)
      expect(result.error.message).to include("Shopify did not answer")
      expect(Rails.logger).to have_received(:error).with(/draft_not_voidable.*StaleDraftOrderError: .*Shopify did not answer/)
    end

    it "the order deleted between lookup and lock is a refusal, not a RecordNotFound" do
      order = make_job_order!(owner: owner, status_key: :being_processed)
      JobOrderStatus.where(job_order_id: order.id).delete_all
      JobOrder.where(id: order.id).delete_all

      result = order.transition!(from: JobStatus::BEING_PROCESSED, to: JobStatus::COMPLETED, actor: staff)

      expect(result.reason).to eq(:order_missing)
      expect(result.message_key).to eq("job_orders.alerts.status_change_order_missing")
    end

    it "a lock wait timeout is a refusal with a retry message" do
      order = quoted_order!(:being_processed)
      allow(order).to receive(:lock!).and_raise(ActiveRecord::LockWaitTimeout)

      result = order.transition!(from: JobStatus::BEING_PROCESSED, to: JobStatus::COMPLETED, actor: staff)

      expect(result.reason).to eq(:busy)
      expect(result.message_key).to eq("job_orders.alerts.status_change_busy")
      expect(status_names(order)).to eq(["Currently being Processed"])
    end

    it "a deadlock is the same refusal" do
      order = quoted_order!(:being_processed)
      allow(order).to receive(:lock!).and_raise(ActiveRecord::Deadlocked)

      expect(order.transition!(from: JobStatus::BEING_PROCESSED, to: JobStatus::COMPLETED, actor: staff).reason).to eq(:busy)
    end

    it "a status row the database rejects (NOT NULL) is an invalid-row refusal" do
      order = quoted_order!(:being_processed)
      allow_any_instance_of(JobOrderStatus).to receive(:save!).and_raise(ActiveRecord::NotNullViolation)

      result = order.transition!(from: JobStatus::BEING_PROCESSED, to: JobStatus::COMPLETED, actor: staff)

      expect(result.reason).to eq(:invalid_status_row)
    end

    it "has en and fr messages for every refusal message key" do
      %i[wrong_state link_spent draft_not_voidable invalid_status_row order_missing busy].each do |reason|
        result = JobOrder::TransitionResult.refused(reason)
        %i[en fr].each do |locale|
          expect(I18n.t(result.message_key, locale: locale, raise: true)).to be_present
          expect(I18n.t(result.zero_order_message_key, locale: locale, raise: true)).to be_present
        end
      end
    end

    it "a refused transition inside a caller's transaction leaves no status row and keeps the draft id" do
      order = quoted_order!(:completed)
      draft = "gid://shopify/DraftOrder/9001"
      order.update_column(:shopify_draft_order_id, draft)
      shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete" }]
      result = nil

      ActiveRecord::Base.transaction do
        result = order.transition!(from: JobStatus::COMPLETED, to: JobStatus::DECLINED, actor: staff)
        # the caller does NOT raise Rollback: the outer transaction commits
      end

      expect(result.reason).to eq(:draft_not_voidable)
      expect(status_names(order)).to eq(["Completed (Waiting for Payment)"])
      expect(reload_free(order).shopify_draft_order_id).to eq(draft)
      expect(order.shopify_draft_order_id).to eq(draft) # and the record in memory agrees
    end
  end
end
