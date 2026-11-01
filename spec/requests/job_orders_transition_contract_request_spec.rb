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

  # Rails turns the raised error into a 500 debug page in request specs (see spec/requests/job_orders_request_spec.rb).
  def expect_missing_status!(name)
    expect(response).to have_http_status(:internal_server_error)
    expect(response.body).to include("JobStatus::Missing").and include(name)
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
      expect(Rails.error).to receive(:report).with(an_instance_of(JobOrder::StatusRowInvalid), hash_including(handled: true))

      result = order.transition!(from: JobStatus.waiting_processed, to: JobStatus.being_processed, actor: nil)

      expect(result).not_to be_ok
      expect(result.reason).to eq(:invalid_status_row)
      expect(result.message_key).to eq("job_orders.alerts.status_change.invalid_status_row")
      expect(status_names(order)).to eq(["Waiting to be Processed"])
    end

    # The workflow statuses are never nil: a status row missing from the table fails closed (JobStatus::Missing, a 500) before
    # anything is written (production has all ten).
    it "approving an order does not look up statuses the request does not use (Declined missing)" do
      order = quoted_order!(:user_approval)
      token = order.approval_token
      JobStatus.where(name: "Declined").delete_all
      JobStatus.reset_lookup_cache!

      patch user_magic_approval_confirmation_job_orders_path, params: { token: token, approved: "true" }

      expect(response).to have_http_status(:ok)
      expect(status_names(order)).to eq(["Waiting for User Approval", "Waiting to be Processed"])
    end

    it "a missing destination status on a staff transition fails closed (JobStatus::Missing, a 500) and records nothing" do
      order = quoted_order!(:waiting_processed)
      JobStatus.where(name: "Currently being Processed").delete_all
      JobStatus.reset_lookup_cache!
      session_login!(staff)

      patch job_order_start_processing_path(order), params: { start_processing: "true" }

      expect_missing_status!("Currently being Processed")
      expect(status_names(order)).to eq(["Waiting to be Processed"])
    end

    it "a missing destination status on the emailed approval fails closed (JobStatus::Missing, a 500) and records nothing" do
      order = quoted_order!(:user_approval)
      token = order.approval_token
      JobStatus.where(name: "Waiting to be Processed").delete_all
      JobStatus.reset_lookup_cache!

      patch user_magic_approval_confirmation_job_orders_path, params: { token: token, approved: "true" }

      expect_missing_status!("Waiting to be Processed")
      expect(status_names(order)).to eq(["Waiting for User Approval"])
    end

    it "a missing status on a quote fails closed (JobStatus::Missing, a 500) and the quote is not saved" do
      order = quoted_order!(:staff_approval)
      task = order.job_tasks.first
      JobStatus.where(name: "Waiting for User Approval").delete_all
      JobStatus.reset_lookup_cache!
      session_login!(staff)

      patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => "77",
                                                   job_order: { staff_comments: "" } }

      expect_missing_status!("Waiting for User Approval")
      expect(order.reload.total_price).to eq(BigDecimal("29.99"))
      expect(status_names(order)).to eq(["Waiting for Staff Approval"])
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "a missing status on a decline fails closed (JobStatus::Missing, a 500) and records nothing" do
      order = quoted_order!(:staff_approval)
      JobStatus.where(name: "Declined").delete_all
      JobStatus.reset_lookup_cache!
      session_login!(staff)

      patch job_order_quote_path(order), params: { approved: "false", job_order: { staff_comments: "" } }

      expect_missing_status!("Declined")
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

  describe "the $0 path in processed" do
    it "marks a $0 order Paid and says so" do
      order = quoted_order!(:being_processed, price: 0)
      session_login!(staff)
      patch job_order_processed_path(order), params: { completed: "true" }

      expect(status_names(order).last(2)).to eq(["Completed (Waiting for Payment)", "Paid (Waiting for Pick-Up)"])
      expect(flash[:notice]).to eq(I18n.t("job_orders.alerts.updated_job_status_to_x", status: JobStatus.paid.t_name))
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
              handled: true, context: hash_including(job_order_id: order.id, where: "JobOrder#transition!",
                                                     operation: /Completed \(Waiting for Payment\).*Paid \(Waiting for Pick-Up\)/,
                                                     reason: :draft_not_voidable)).once
      allow(Rails.logger).to receive(:error)

      result = order.transition!(from: JobStatus.completed, to: JobStatus.paid, actor: staff)

      expect(result.reason).to eq(:draft_not_voidable)
      expect(result.error.message).to include("Shopify did not answer")
      expect(Rails.logger).to have_received(:error).with(/draft_not_voidable.*StaleDraftOrderError: .*Shopify did not answer/)
    end

    it "the order deleted between lookup and lock is a refusal, not a RecordNotFound" do
      order = make_job_order!(owner: owner, status_key: :being_processed)
      JobOrderStatus.where(job_order_id: order.id).delete_all
      JobOrder.where(id: order.id).delete_all

      result = order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff)

      expect(result.reason).to eq(:order_missing)
      expect(result.message_key).to eq("job_orders.alerts.status_change.order_missing")
    end

    it "a lock wait timeout is a refusal with a retry message" do
      order = quoted_order!(:being_processed)
      allow(order).to receive(:lock!).and_raise(ActiveRecord::LockWaitTimeout)

      result = order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff)

      expect(result.reason).to eq(:busy)
      expect(result.message_key).to eq("job_orders.alerts.status_change.busy")
      expect(status_names(order)).to eq(["Currently being Processed"])
    end

    # Round 4 review 10: a deadlock is a lock-order bug, not a race lost: it is reported (the user still sees "try
    # again"); only a lock wait timeout and a vanished order are benign.
    it "a deadlock is its own refusal with the retry message, and it is reported" do
      order = quoted_order!(:being_processed)
      expect(Rails.error).to receive(:report)
        .with(an_instance_of(ActiveRecord::Deadlocked),
              handled: true, context: hash_including(job_order_id: order.id, where: "JobOrder#transition!")).once

      # raised from inside the work (the status row's insert), not from the row lock
      result = order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff) do
        raise ActiveRecord::Deadlocked
      end

      expect(result.reason).to eq(:deadlock)
      expect(result.message_key).to eq("job_orders.alerts.status_change.busy")
      expect(status_names(order)).to eq(["Currently being Processed"])
    end

    it "a status row the database rejects (NOT NULL) is an invalid-row refusal" do
      order = quoted_order!(:being_processed)
      allow_any_instance_of(JobOrderStatus).to receive(:save!).and_raise(ActiveRecord::NotNullViolation)

      result = order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff)

      expect(result.reason).to eq(:invalid_status_row)
    end

    it "has en and fr messages for every reason with its own message, and the generic ones for the rest" do
      (JobOrder::TransitionResult::REASONS_WITH_MESSAGE + %i[wrong_state link_spent]).each do |reason|
        result = JobOrder::TransitionResult.refused(reason)
        %i[en fr].each do |locale|
          expect(I18n.t(result.message_key, locale: locale, raise: true)).to be_present
          expect(I18n.t(result.zero_order_message_key, locale: locale, raise: true)).to be_present
        end
      end
      expect(JobOrder::TransitionResult.refused(:wrong_state).message_key).to eq("job_orders.alerts.error_while_updating")
      expect(JobOrder::TransitionResult.refused(:wrong_state).zero_order_message_key)
        .to eq("job_orders.alerts.zero_order_not_marked_paid.other")
    end

    # A race lost is not a failure: nothing goes to the error reporter, no error-level log.
    it "does not report or error-log an order deleted before the lock" do
      order = make_job_order!(owner: owner, status_key: :being_processed)
      JobOrderStatus.where(job_order_id: order.id).delete_all
      JobOrder.where(id: order.id).delete_all
      expect(Rails.error).not_to receive(:report)
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:info)

      order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff)

      expect(Rails.logger).not_to have_received(:error)
      expect(Rails.logger).to have_received(:info).with(/order_missing/)
    end

    it "does not report or error-log a lock wait timeout" do
      order = quoted_order!(:being_processed)
      allow(order).to receive(:lock!).and_raise(ActiveRecord::LockWaitTimeout)
      expect(Rails.error).not_to receive(:report)
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:info)

      expect(order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff).reason).to eq(:busy)

      expect(Rails.logger).not_to have_received(:error)
      expect(Rails.logger).to have_received(:info).with(/busy/)
    end

    it "a transition is its own transaction: inside a caller's transaction it refuses to run" do
      order = quoted_order!(:being_processed)

      expect do
        ActiveRecord::Base.transaction do
          order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff)
        end
      end.to raise_error(ArgumentError, /must run as its own transaction/)
    end

    it "bounds the lock wait of its own transaction" do
      order = quoted_order!(:being_processed)
      seen = nil
      allow(order).to receive(:lock!).and_wrap_original do |m, *args|
        seen = JobOrder.connection.select_value("SELECT current_setting('lock_timeout')")
        m.call(*args)
      end

      order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff)

      expect(seen).to eq(ApplicationRecord::LOCK_TIMEOUT)
    end

    it "a refusal rolls back everything: the block's writes, the status row and the draft id" do
      order = quoted_order!(:completed)
      draft = "gid://shopify/DraftOrder/9001"
      order.update_column(:shopify_draft_order_id, draft)
      shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete" }]

      result = order.transition!(from: JobStatus.completed, to: JobStatus.declined, actor: staff) do
        order.job_quote_line_items.create!(description: "Rush", price: 5)
      end

      expect(result.reason).to eq(:draft_not_voidable)
      expect(status_names(order)).to eq(["Completed (Waiting for Payment)"])
      expect(order.job_quote_line_items.count).to eq(0)
      expect(reload_free(order).shopify_draft_order_id).to eq(draft)
      expect(order.shopify_draft_order_id).to eq(draft) # and the record in memory agrees (reloaded)
    end

    it "the block's validation failure is a :change_invalid refusal with its messages, not an invalid-status-row one" do
      order = quoted_order!(:being_processed)

      result = order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff) do
        order.job_quote_line_items.create!(description: "x", price: -1)
      end

      expect(result.reason).to eq(:change_invalid)
      expect(result.error).to be_a(JobOrder::ChangeInvalid)
      expect(result.error.message).to match(/price/i)
      expect(status_names(order)).to eq(["Currently being Processed"])
    end
  end
end
