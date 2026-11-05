# frozen_string_literal: true

require "rails_helper"

# Round 4 review: every change to a job order's status or existence is ONE locked operation
# (JobOrder#locked_operation): its own bounded transaction, the row lock, the status read under it. Only the lock's
# own failures (order gone, lock timeout, deadlock) are told apart as lock failures; what the work raises is
# classified by its own class or propagates. A deleted order's Shopify draft is settled with the delete.
RSpec.describe "Job order locked operations", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }
  let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/invoice" } }
  let(:draft_id) { "gid://shopify/DraftOrder/9001" }

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

  def quoted_order!(status_key, price: 29.99, draft: false)
    order = make_job_order!(owner: owner, status_key: status_key)
    order.job_tasks.create!(title: "Task #1", job_type: JobType.find_by!(name: "3D Print"))
         .build_job_task_quote(price: price, service_price: 0, service_quantity: 0).save!
    order.update_column(:shopify_draft_order_id, draft_id) if draft
    order.reload
  end

  # ------------------------------------------------ 1. the skip is keyed on the source status

  describe "leaving PAID asks Shopify nothing; every other source settles the draft" do
    it "PAID -> PICKED_UP: no Shopify call, even while Shopify is down" do
      order = quoted_order!(:paid, draft: true)
      shopify.status = 502

      result = order.transition!(from: JobStatus.paid, to: JobStatus.picked_up, actor: staff)

      expect(result).to be_ok
      expect(shopify.calls).to be_empty
      expect(status_names(order).last).to eq("Picked-Up")
    end

    it "COMPLETED -> PICKED_UP (a path that does not exist today) still settles the draft: deleted, fail closed" do
      order = quoted_order!(:completed, draft: true)

      result = order.transition!(from: JobStatus.completed, to: JobStatus.picked_up, actor: staff)

      expect(result).to be_ok
      expect(shopify_ops).to eq(%w[getDraftOrder draftOrderDelete]) # a paid destination asks first
      expect(order.reload.shopify_draft_order_id).to be_nil
    end

    it "COMPLETED -> PICKED_UP is refused when Shopify cannot confirm the draft" do
      order = quoted_order!(:completed, draft: true)
      shopify.status = 502

      result = order.transition!(from: JobStatus.completed, to: JobStatus.picked_up, actor: staff)

      expect(result.reason).to eq(:draft_not_voidable)
      expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
    end
  end

  # ------------------------------------------------ 2. what the work raises is not a lock failure

  describe "an exception raised by the work is not relabelled as a lock failure" do
    def transition_with(order, &work)
      order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff, &work)
    end

    {
      "RecordNotFound (a bad signed blob id in the quote)" => ActiveRecord::RecordNotFound,
      "NotNullViolation (a price column)" => ActiveRecord::NotNullViolation
    }.each do |label, error|
      it "#{label} propagates as itself; nothing is committed, nothing is reported as a refusal" do
        order = quoted_order!(:being_processed)
        expect(Rails.error).not_to receive(:report)

        expect { transition_with(order) { raise error } }.to raise_error(error)
        expect(status_names(order)).to eq(["Currently being Processed"])
      end
    end

    it "the same holds for the owner change's block" do
      order = quoted_order!(:draft)
      expect { order.apply_owner_change!(actor: owner) { raise ActiveRecord::RecordNotFound } }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "a database error while a Shopify answer is being stored is not turned into a Shopify refusal" do
      order = quoted_order!(:completed)
      allow_any_instance_of(JobOrder).to receive(:store_shopify_draft_order_id).and_raise(ActiveRecord::StatementInvalid)

      expect { order.checkout_link }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "the lock's own failures are results: gone, busy, deadlock" do
      {
        ActiveRecord::RecordNotFound => :order_missing,
        ActiveRecord::LockWaitTimeout => :busy,
        ActiveRecord::Deadlocked => :deadlock
      }.each do |error, reason|
        order = quoted_order!(:being_processed)
        allow(order).to receive(:lock!).and_raise(error)
        result = transition_with(order) { raise "never runs" }
        expect(result.reason).to eq(reason)
        expect(result.status).to be_nil
      end
    end

    it "a status row the database rejects is invalid_status_row; the work's own NOT NULL is not" do
      order = quoted_order!(:being_processed)
      allow_any_instance_of(JobOrderStatus).to receive(:save!).and_raise(ActiveRecord::NotNullViolation)

      expect(transition_with(order).reason).to eq(:invalid_status_row)
    end
  end

  # ------------------------------------------------ 3. Shopify calls under the lock

  describe "Shopify calls under the lock" do
    it "a destination that is not paid deletes first: ONE call on the normal path" do
      order = quoted_order!(:completed, draft: true)
      order.transition!(from: JobStatus.completed, to: JobStatus.declined, actor: staff)

      expect(shopify_ops).to eq(%w[draftOrderDelete])
      expect(order.reload.shopify_draft_order_id).to be_nil
    end

    it "a paid destination asks first, and keeps a draft Shopify reports COMPLETED (one call)" do
      order = quoted_order!(:completed, draft: true)
      shopify.draft_status = "COMPLETED"
      order.transition!(from: JobStatus.completed, to: JobStatus.paid, actor: staff)

      expect(shopify_ops).to eq(%w[getDraftOrder])
      expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    end

    it "a paid destination deletes an open draft (paid in store): fetch, then delete" do
      order = quoted_order!(:completed, draft: true)
      order.transition!(from: JobStatus.completed, to: JobStatus.paid, actor: staff)

      expect(shopify_ops).to eq(%w[getDraftOrder draftOrderDelete])
    end

    context "when the delete returned no deletedId" do
      before { shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete" }] }

      it "gone on Shopify: the id is cleared and the transition goes through (delete, fetch)" do
        order = quoted_order!(:completed, draft: true)
        shopify.draft_missing = true

        result = order.transition!(from: JobStatus.completed, to: JobStatus.declined, actor: staff)

        expect(result).to be_ok
        expect(shopify_ops).to eq(%w[draftOrderDelete getDraftOrder])
        expect(order.reload.shopify_draft_order_id).to be_nil
      end

      it "COMPLETED on Shopify (paid through it): refused, fail closed, the id kept" do
        order = quoted_order!(:completed, draft: true)
        shopify.draft_status = "COMPLETED"

        result = order.transition!(from: JobStatus.completed, to: JobStatus.declined, actor: staff)

        expect(result.reason).to eq(:draft_not_voidable)
        expect(result.error.message).to include("already paid")
        expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
        expect(order.reload.shopify_draft_order_id).to eq(draft_id)
      end

      it "still open on Shopify: refused with Shopify's reason" do
        order = quoted_order!(:completed, draft: true)

        result = order.transition!(from: JobStatus.completed, to: JobStatus.declined, actor: staff)

        expect(result.reason).to eq(:draft_not_voidable)
        expect(result.error.message).to include("cannot delete")
      end

      it "the fetch itself fails: refused" do
        order = quoted_order!(:completed, draft: true)
        allow(shopify).to receive(:query).and_wrap_original do |m, **kw|
          kw[:query].include?("getDraftOrder") ? raise("boom") : m.call(**kw)
        end

        expect(order.transition!(from: JobStatus.completed, to: JobStatus.declined, actor: staff).reason)
          .to eq(:draft_not_voidable)
        expect(order.reload.shopify_draft_order_id).to eq(draft_id)
      end
    end
  end

  # ------------------------------------------------ 4. "already paid" comes from the status the operation read

  describe "a refused quote decides 'already paid' from the status read under the lock" do
    it "carries the status in the result" do
      order = quoted_order!(:paid)
      result = order.transition!(from: JobOrder.quotable_statuses, to: JobStatus.user_approval, actor: staff)

      expect(result.reason).to eq(:wrong_state)
      expect(result.status).to eq(JobStatus.paid)
    end

    it "the controller does not read the statuses again after the transition" do
      order = quoted_order!(:paid)
      session_login!(staff)
      after_transition = false
      allow_any_instance_of(JobOrder).to receive(:transition!).and_wrap_original do |m, *args, **kw, &blk|
        m.call(*args, **kw, &blk).tap { after_transition = true }
      end
      late_reads = []
      counter = lambda do |*, payload|
        late_reads << payload[:sql] if after_transition && payload[:sql].match?(/FROM "job_order_statuses"/)
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        patch job_order_quote_path(order), params: { approved: "true", job_order: { staff_comments: "" } }
      end

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.quote_refused_paid"))
      expect(late_reads).to be_empty
    end

    it "a refusal that is not 'paid' (a lock timeout) does not say 'already paid'" do
      order = quoted_order!(:paid)
      session_login!(staff)
      allow_any_instance_of(JobOrder).to receive(:lock!).and_raise(ActiveRecord::LockWaitTimeout)
      patch job_order_quote_path(order), params: { approved: "true", job_order: { staff_comments: "" } }

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.status_change.busy"))
    end
  end

  # ------------------------------------------------ 5. the owner change is bounded and mapped

  describe "an owner change (JobTasksController) under contention" do
    def edit_task!(order)
      patch job_order_job_task_path(order, order.job_tasks.first),
            params: { step: "1", job_task: { job_type_id: JobType.find_by!(name: "Laser Cut").id } }
    end

    it "runs in its own bounded transaction" do
      order = quoted_order!(:draft)
      session_login!(owner)
      seen = nil
      allow_any_instance_of(JobOrder).to receive(:lock!).and_wrap_original do |m, *args|
        seen = JobOrder.connection.select_value("SELECT current_setting('lock_timeout')")
        m.call(*args)
      end
      edit_task!(order)

      expect(seen).to eq(ApplicationRecord::LOCK_TIMEOUT)
      expect(order.reload.job_tasks.first.job_type.name).to eq("Laser Cut")
    end

    {
      ActiveRecord::LockWaitTimeout => "owner_change_busy",
      ActiveRecord::Deadlocked => "owner_change_busy"
    }.each do |error, key|
      it "#{error.name.demodulize}: a message and the order page, not a 500; nothing changed" do
        order = quoted_order!(:draft)
        session_login!(owner)
        allow_any_instance_of(JobOrder).to receive(:lock!).and_raise(error)
        edit_task!(order)

        expect(response).to redirect_to(job_order_path(order))
        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.#{key}"))
        expect(order.reload.job_tasks.first.job_type.name).to eq("3D Print")
      end
    end

    it "an order deleted before the lock: a message and the order list, not a 500" do
      order = quoted_order!(:draft)
      session_login!(owner)
      allow_any_instance_of(JobOrder).to receive(:lock!).and_raise(ActiveRecord::RecordNotFound)
      edit_task!(order)

      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.owner_change_order_missing"))
    end

    it "an order soft-deleted between the lookup and the lock is refused like a vanished one" do
      order = quoted_order!(:draft)
      session_login!(owner)
      allow_any_instance_of(JobOrder).to receive(:lock!).and_wrap_original do |m, *args|
        JobOrder.where(id: order.id).update_all(is_deleted: true)
        m.call(*args)
      end
      edit_task!(order)

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.owner_change_order_missing"))
      expect(order.reload.job_tasks.first.job_type.name).to eq("3D Print")
    end
  end

  # ------------------------------------------------ 6. strong params

  describe "the quote form's params" do
    it "a job_order that is not a hash is no staff comment, not a 500" do
      order = quoted_order!(:staff_approval)
      task = order.job_tasks.first
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "true", job_order: "x",
                                                   "job_task_quote_price_#{task.id}" => "12" }

      expect(response).to redirect_to(job_order_path(order.id))
      expect(status_names(order).last).to eq("Waiting for User Approval")
    end

    it "stores the staff comment when given" do
      order = quoted_order!(:staff_approval)
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "true", job_order: { staff_comments: "see notes" } }

      expect(order.reload.staff_comments).to eq("see notes")
    end
  end

  # ------------------------------------------------ 7. the quote's chat message is after the commit

  describe "the quote's chat message" do
    before do
      # someone to notify: the owner has already written on the order
      ChatMessage.create!(job_order: quoted_for_chat, message: "hello", sender: owner)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    let!(:quoted_for_chat) { quoted_order!(:completed, draft: true) }

    def jobs
      ActiveJob::Base.queue_adapter.enqueued_jobs
    end

    it "a refused re-quote with a comment creates no chat message and enqueues no job" do
      shopify.status = 502 # the old draft cannot be voided: the whole quote is refused
      session_login!(staff)
      patch job_order_quote_path(quoted_for_chat), params: { approved: "true", user_comments: "new price",
                                                             job_order: { staff_comments: "" } }

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.requote_draft_order_failed"))
      expect(ChatMessage.where(job_order_id: quoted_for_chat.id).pluck(:message)).to eq(["hello"])
      expect(jobs).to be_empty
    end

    it "a committed re-quote posts the comment (and its notification) after the commit" do
      session_login!(staff)
      patch job_order_quote_path(quoted_for_chat), params: { approved: "true", user_comments: "new price",
                                                             job_order: { staff_comments: "" } }

      expect(ChatMessage.where(job_order_id: quoted_for_chat.id).pluck(:message)).to eq(["hello", "new price"])
      expect(jobs.map { |j| j[:args].first(2) }).to include(%w[ChatMessageMailer new_message])
    end

    it "a committed decline posts the comment as before" do
      session_login!(staff)
      patch job_order_quote_path(quoted_for_chat), params: { approved: "false", user_comments: "no thanks" }

      expect(ChatMessage.where(job_order_id: quoted_for_chat.id).pluck(:message)).to eq(["hello", "no thanks"])
    end
  end

  # ------------------------------------------------ 8. invalid input shows its messages, logged once

  describe "a quote whose writes do not validate" do
    it "shows the validation messages (escaped) and logs the refusal once" do
      order = quoted_order!(:staff_approval)
      task = order.job_tasks.first
      session_login!(staff)
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
      bad = JobTaskQuote.new.tap { |q| q.errors.add(:base, "<script>alert(1)</script> is not a price") }
      allow_any_instance_of(JobTaskQuote).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(bad))

      patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => "5",
                                                   job_order: { staff_comments: "" } }

      expect(response).to redirect_to(job_order_path(order.id))
      expect(flash[:alert]).to start_with(I18n.t("job_orders.alerts.error_while_updating"))
      expect(flash[:alert]).to include("&lt;script&gt;alert(1)&lt;/script&gt; is not a price")
      expect(flash[:alert]).not_to include("<script>")
      expect(Rails.logger).to have_received(:info).with(/change_invalid.*is not a price/).once
      expect(Rails.logger).not_to have_received(:error)
      expect(status_names(order)).to eq(["Waiting for Staff Approval"])
    end
  end

  # ------------------------------------------------ 10. deadlocks are reported, timeouts and gone orders are not

  describe "what is reported" do
    it "a deadlock goes to the error reporter, with where:, and the user is told to try again" do
      order = quoted_order!(:being_processed)
      session_login!(staff)
      allow_any_instance_of(JobOrderStatus).to receive(:save!).and_raise(ActiveRecord::Deadlocked) # inside the work
      expect(Rails.error).to receive(:report)
        .with(an_instance_of(ActiveRecord::Deadlocked),
              handled: true, context: hash_including(job_order_id: order.id, where: "JobOrder#transition!")).once

      patch job_order_processed_path(order), params: { completed: "true" }

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.status_change.busy"))
    end

    it "a lock wait timeout and a vanished order are not reported" do
      expect(Rails.error).not_to receive(:report)
      [ActiveRecord::LockWaitTimeout, ActiveRecord::RecordNotFound].each do |error|
        order = quoted_order!(:being_processed)
        allow(order).to receive(:lock!).and_raise(error)
        expect(order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff)).not_to be_ok
      end
    end
  end

  # ------------------------------------------------ deleting an order settles its draft

  describe "DELETE /job_orders/:id settles the Shopify draft with the delete" do
    it "deletes the open draft and soft-deletes the order, as one locked operation" do
      order = quoted_order!(:completed, draft: true)
      session_login!(admin)
      delete job_order_path(order)

      expect(response).to redirect_to(admin_job_orders_path)
      expect(flash[:notice]).to eq("Job order deleted successfully.")
      expect(order.reload.is_deleted).to be(true)
      expect(order.shopify_draft_order_id).to be_nil
      expect(shopify_ops).to eq(%w[draftOrderDelete])
    end

    it "does not ask Shopify about an order without a draft" do
      order = quoted_order!(:completed)
      session_login!(admin)
      delete job_order_path(order)

      expect(order.reload.is_deleted).to be(true)
      expect(shopify.calls).to be_empty
    end

    it "is refused, with the order untouched, when Shopify will not delete the draft (fail closed)" do
      order = quoted_order!(:completed, draft: true)
      shopify.status = 502
      session_login!(admin)
      delete job_order_path(order)

      expect(response).to redirect_to(job_order_path(order))
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.delete_refused.draft_not_voidable"))
      expect(order.reload.is_deleted).to be(false)
      expect(order.shopify_draft_order_id).to eq(draft_id)
    end

    it "is refused when the draft was paid through Shopify (COMPLETED): the payment record stays" do
      order = quoted_order!(:completed, draft: true)
      shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete" }]
      shopify.draft_status = "COMPLETED"
      session_login!(admin)
      delete job_order_path(order)

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.delete_refused.draft_not_voidable"))
      expect(order.reload.is_deleted).to be(false)
    end

    it "a lock timeout: a message, nothing deleted" do
      order = quoted_order!(:completed, draft: true)
      session_login!(admin)
      allow_any_instance_of(JobOrder).to receive(:lock!).and_raise(ActiveRecord::LockWaitTimeout)
      delete job_order_path(order)

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.delete_refused.busy"))
      expect(order.reload.is_deleted).to be(false)
    end

    it "has en and fr messages for every reason a delete is refused for" do
      JobOrder::TransitionResult::DELETE_REASONS.each do |reason|
        key = JobOrder::TransitionResult.refused(reason).message_key("job_orders.alerts.delete_refused",
                                                                      reasons: JobOrder::TransitionResult::DELETE_REASONS)
        %i[en fr].each { |locale| expect(I18n.t(key, locale: locale, raise: true)).to be_present }
      end
      %w[owner_change_busy owner_change_order_missing].each do |key|
        %i[en fr].each { |locale| expect(I18n.t("job_orders.alerts.#{key}", locale: locale, raise: true)).to be_present }
      end
    end

    it "soft-deleting an order without a status settles as :unpaid" do
      order = quoted_order!(:completed, draft: true)
      JobOrderStatus.where(job_order_id: order.id).delete_all

      expect(JobOrder.draft_settlement(nil, JobOrder::DELETED)).to eq(:unpaid)
      result = JobOrder.find(order.id).soft_delete!(actor: admin)

      expect(result).to be_ok
      expect(order.reload.is_deleted).to be(true)
      expect(shopify_ops).to include("draftOrderDelete")
    end

    it "an order deleted twice (a race lost) is order_missing, and no second Shopify call" do
      order = quoted_order!(:completed, draft: true)
      expect(order.soft_delete!(actor: admin)).to be_ok
      shopify.calls.clear

      expect(JobOrder.find(order.id).soft_delete!(actor: admin).reason).to eq(:order_missing)
      expect(shopify.calls).to be_empty
    end
  end

  # ------------------------------------------------ deleting a paid order keeps the payment record

  describe "deleting an order whose money was taken" do
    %i[paid picked_up].each do |status_key|
      it "#{status_key}: a COMPLETED draft is kept (the payment record) and the order is deleted" do
        order = quoted_order!(status_key, draft: true)
        shopify.draft_status = "COMPLETED"
        session_login!(admin)

        delete job_order_path(order)

        expect(flash[:notice]).to eq("Job order deleted successfully.")
        expect(order.reload.is_deleted).to be(true)
        expect(order.shopify_draft_order_id).to eq(draft_id)
        expect(shopify_ops).to eq(%w[getDraftOrder])
      end

      it "#{status_key}: a draft Shopify no longer knows is cleared" do
        order = quoted_order!(status_key, draft: true)
        shopify.draft_missing = true
        session_login!(admin)

        delete job_order_path(order)

        expect(order.reload.is_deleted).to be(true)
        expect(order.shopify_draft_order_id).to be_nil
      end

      it "#{status_key}: an open draft (paid in store) is deleted, so it cannot be paid again" do
        order = quoted_order!(status_key, draft: true)
        session_login!(admin)

        delete job_order_path(order)

        expect(order.reload.is_deleted).to be(true)
        expect(order.shopify_draft_order_id).to be_nil
        expect(shopify_ops).to eq(%w[getDraftOrder draftOrderDelete])
      end
    end

    it "settles by (status, destination): one rule for transitions, deletes and the rake" do
      paid = [JobStatus.paid, JobStatus.picked_up]
      unpaid = [JobStatus.draft, JobStatus.staff_approval, JobStatus.user_approval, JobStatus.being_processed]
      paid.each do |from|
        expect(JobOrder.draft_settlement(from, JobOrder::DELETED)).to eq(:paid)
        expect(JobOrder.draft_settlement(nil, from)).to eq(:paid)
      end
      unpaid.each do |from|
        expect(JobOrder.draft_settlement(from, JobOrder::DELETED)).to eq(:unpaid)
        expect(JobOrder.draft_settlement(from, JobStatus.paid)).to eq(:paid)
        expect(JobOrder.draft_settlement(from, JobStatus.declined)).to eq(:unpaid)
      end
      expect(JobOrder.draft_settlement(JobStatus.paid, JobStatus.picked_up)).to eq(:none)
      expect(JobOrder.draft_settlement(JobStatus.being_processed, JobStatus.completed)).to eq(:none)
    end
  end

  # ------------------------------------------------ lock errors raised inside the work

  describe "lock errors raised inside the work" do
    it "a child-row lock timeout during an owner change is :busy with a message, nothing changed" do
      order = quoted_order!(:draft)
      result = order.apply_owner_change!(actor: owner) { raise ActiveRecord::LockWaitTimeout }

      expect(result.reason).to eq(:busy)
      expect(result.message_key).to eq("job_orders.alerts.status_change.busy")
      expect(I18n.t(result.message_key)).to be_present
    end

    it "a deadlock in the work is :deadlock and reported" do
      order = quoted_order!(:draft)
      expect(Rails.error).to receive(:report).with(an_instance_of(ActiveRecord::Deadlocked), hash_including(handled: true)).once

      expect(order.apply_owner_change!(actor: owner) { raise ActiveRecord::Deadlocked }.reason).to eq(:deadlock)
    end

    it "a RecordNotFound from the work still propagates (only the row lock means the order is gone)" do
      order = quoted_order!(:draft)
      expect { order.apply_owner_change!(actor: owner) { raise ActiveRecord::RecordNotFound } }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "DELETE of an order that no longer exists" do
    {
      "an owner" => [:owner, :job_orders_path],
      "an admin" => [:admin, :admin_job_orders_path]
    }.each do |label, (who, list)|
      it "redirects #{label} to their order list, where the message is shown" do
        order = quoted_order!(:draft)
        session_login!(send(who))
        allow_any_instance_of(JobOrder).to receive(:lock!).and_raise(ActiveRecord::RecordNotFound)

        delete job_order_path(order)

        expect(response).to redirect_to(send(list))
        follow_redirect!
        expect(response.body).to include(I18n.t("job_orders.alerts.delete_refused.order_missing"))
      end
    end
  end

  describe "who may delete (the server enforces what the page offers)" do
    it "an owner deleting a PAID order is refused, with a message; nothing changes" do
      order = quoted_order!(:paid, draft: true)
      shopify.draft_status = "COMPLETED"
      session_login!(owner)

      delete job_order_path(order)

      expect(response).to redirect_to(job_order_path(order))
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.delete_refused.not_deletable"))
      expect(order.reload.is_deleted).to be(false)
      expect(shopify.calls).to be_empty
    end

    it "an owner deleting a DRAFT order is allowed" do
      order = quoted_order!(:draft)
      session_login!(owner)

      delete job_order_path(order)

      expect(order.reload.is_deleted).to be(true)
    end

    {
      "DRAFT" => :draft,
      "STAFF_APPROVAL" => :staff_approval
    }.each do |label, status_key|
      it "staff who do not own a customer's #{label} order cannot delete it" do
        order = quoted_order!(status_key, draft: true)
        session_login!(staff)

        delete job_order_path(order)

        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.delete_refused.not_deletable"))
        expect(order.reload.is_deleted).to be(false)
        expect(shopify.calls).to be_empty
      end

      it "another customer cannot delete someone else's #{label} order" do
        order = quoted_order!(status_key)
        session_login!(create(:user, :regular_user))

        delete job_order_path(order)

        expect(order.reload.is_deleted).to be(false)
      end

      it "an admin can delete a customer's #{label} order" do
        order = quoted_order!(status_key)
        session_login!(admin)

        delete job_order_path(order)

        expect(order.reload.is_deleted).to be(true)
      end
    end

    describe "the order page offers Delete exactly when the server would accept it" do
      def delete_button?(order)
        get job_order_path(order)
        expect(response).to have_http_status(:ok)
        Nokogiri::HTML(response.body).css("form[action='#{job_order_path(order)}'] input[name='_method'][value='delete']").any?
      end

      # [who, status] => shown
      {
        [:owner, :draft] => true,
        [:owner, :staff_approval] => true,
        [:owner, :user_approval] => false,
        [:owner, :paid] => false,
        [:staff, :draft] => false,
        [:staff, :user_approval] => false,
        [:admin, :draft] => true,
        [:admin, :user_approval] => true,
        [:admin, :paid] => true
      }.each do |(who, status_key), shown|
        it "#{who} on a #{status_key} order: #{shown ? 'shown' : 'hidden'}" do
          order = quoted_order!(status_key)
          session_login!(send(who))

          expect(delete_button?(order)).to be(shown)
        end
      end
    end

    it "staff who own an editable order can delete it" do
      order = make_job_order!(owner: staff, status_key: :draft)
      session_login!(staff)

      delete job_order_path(order)

      expect(order.reload.is_deleted).to be(true)
    end

    it "staff who are not admins are held to the same rule" do
      order = quoted_order!(:being_processed)
      session_login!(staff)

      delete job_order_path(order)

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.delete_refused.not_deletable"))
      expect(order.reload.is_deleted).to be(false)
    end

    it "an admin deleting a PAID order is allowed and the COMPLETED draft is kept" do
      order = quoted_order!(:paid, draft: true)
      shopify.draft_status = "COMPLETED"
      session_login!(admin)

      delete job_order_path(order)

      expect(order.reload.is_deleted).to be(true)
      expect(order.shopify_draft_order_id).to eq(draft_id)
    end
  end

  # ------------------------------------------------ what is reported

  describe "a refusal that is only a lost race" do
    it "a busy refusal is logged, not reported as an error" do
      order = quoted_order!(:draft)
      expect(Rails.error).not_to receive(:report)

      expect(order.apply_owner_change!(actor: owner) { raise ActiveRecord::LockWaitTimeout }.reason).to eq(:busy)
    end
  end

  # ------------------------------------------------ nothing collects money for a deleted order

  describe "a deleted order is never operated on" do
    it "/pay creates no draft for an order deleted after the token was resolved" do
      order = quoted_order!(:completed)
      token = order.pay_token
      allow(JobOrder).to receive(:from_pay_token).and_wrap_original do |m, *args|
        m.call(*args).tap { JobOrder.where(id: order.id).update_all(is_deleted: true) } # deleted right after
      end

      get pay_job_orders_path, params: { token: token }

      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.pay_magic_link_expired"))
      expect(shopify_ops).not_to include("draftOrderCreate")
      expect(order.reload.shopify_draft_order_id).to be_nil
    end

    it "/pay with the token of an order already deleted is expired" do
      order = quoted_order!(:completed)
      token = order.pay_token
      order.soft_delete!(actor: admin)

      get pay_job_orders_path, params: { token: token }
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.pay_magic_link_expired"))
    end

    it "a transition on an order deleted before its lock is order_missing" do
      order = quoted_order!(:being_processed)
      JobOrder.where(id: order.id).update_all(is_deleted: true)

      result = order.transition!(from: JobStatus.being_processed, to: JobStatus.completed, actor: staff)

      expect(result.reason).to eq(:order_missing)
      expect(status_names(order)).to eq(["Currently being Processed"])
    end
  end
end
