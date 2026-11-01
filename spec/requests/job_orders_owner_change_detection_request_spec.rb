# frozen_string_literal: true

require "rails_helper"

# a wizard write on a quoted order sends it back to
# staff only when it changed what is billed (quote fingerprint) or what is made
# (work fingerprint). Its own validation failures are task errors and roll the
# whole step back. A send-back that cannot be written is a reported "could not
# send back" error with nothing committed, never a task error, never swallowed.
RSpec.describe "Owner changes: what counts, and how failures surface", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:admin) { create(:user, :admin) }
  let(:print_type) { JobType.find_by!(name: "3D Print") }
  let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/invoice" } }
  let(:draft_id) { "gid://shopify/DraftOrder/9001" }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status.name }
  end

  def requote_mails
    ActiveJob::Base.queue_adapter.enqueued_jobs
                   .select { |j| j[:job] == ActionMailer::MailDeliveryJob && j[:args].first(2) == %w[JobOrderMailer send_job_requote_needed] }
  end

  # COMPLETED, with a current draft. Task #1: 3D Print + Polish option (quoted 4); Task #2: 3D Print.
  def quoted_order!
    order = make_job_order!(owner: owner, status_key: :completed)
    polish = JobOption.create!(name: "Polish", fee: 1).tap { |o| o.job_types << print_type }
    task1 = order.job_tasks.create!(title: "Task #1", job_type: print_type)
    task1.job_task_options.create!(job_option: polish)
    task1.build_job_task_quote(price: 40, service_price: 0, service_quantity: 0).save!
    task1.job_task_quote.job_task_quote_options.create!(job_option: polish, price: 4)
    order.job_tasks.create!(title: "Task #2", job_type: print_type)
         .build_job_task_quote(price: 10, service_price: 0, service_quantity: 0).save!
    order.update_columns(shopify_draft_order_id: draft_id,
                         shopify_draft_order_fingerprint: JobOrder.find(order.id).quote_fingerprint)
    order.reload
  end

  def task1(order) = order.job_tasks.find_by!(title: "Task #1")

  def expect_not_sent_back(order)
    expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
    expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    expect(shopify.calls).to be_empty
    expect(requote_mails).to be_empty
  end

  describe "no-op and non-billing writes keep the quote" do
    it "an admin clicking Next on step 1 without changing anything" do
      order = quoted_order!
      session_login!(admin)
      patch job_order_job_task_path(order, task1(order)),
            params: { step: "1", job_task: { job_type_id: print_type.id } }
      expect_not_sent_back(order)
    end

    it "an admin re-submitting step 3 with the same options" do
      order = quoted_order!
      session_login!(admin)
      polish = JobOption.find_by!(name: "Polish")
      patch job_order_job_task_path(order, task1(order)),
            params: { step: "3", job_task: { job_task_options_attributes: [{ job_option_id: polish.id }] } }
      expect(task1(order).job_task_quote.job_task_quote_options.count).to eq(1)
      expect_not_sent_back(order)
    end

    it "Add another task, then leaving the blank task (it bills nothing), then deleting it" do
      order = quoted_order!
      session_login!(owner)
      patch job_order_job_task_path(order, task1(order)), params: { step: "4", add_another: "true" }
      expect(order.reload.job_tasks.count).to eq(3)
      expect_not_sent_back(order)

      blank = order.job_tasks.order(:id).last
      delete job_order_job_task_path(order, blank)
      expect(order.reload.job_tasks.count).to eq(2)
      expect_not_sent_back(order)
    end

    it "comments alone: posted to the chat, the order stays quoted" do
      order = quoted_order!
      session_login!(owner)
      patch job_order_job_task_path(order, task1(order)),
            params: { step: "4", comments: "blue please", save_draft: "true" }
      expect(order.chat_messages.pluck(:message)).to eq(["blue please"])
      expect_not_sent_back(order)
    end

    it "filling in the blank task later does send the order back (it now asks for work)" do
      order = quoted_order!
      session_login!(owner)
      post job_order_job_tasks_path(order)
      expect_not_sent_back(order)

      blank = order.reload.job_tasks.order(:id).last
      patch job_order_job_task_path(order, blank), params: { step: "1", job_task: { job_type_id: print_type.id } }
      expect(status_names(order).last).to eq("Waiting for Staff Approval")
      expect(order.reload.shopify_draft_order_id).to be_nil
    end
  end

  describe "the step's own validation failures" do
    # An already-selected option is found, not built, so the task's autosave never sees it: its failed update used
    # to vanish while the rest of the step committed (and sent the order back).
    it "an invalid file on an already-selected option fails the whole step: nothing saved, no send-back" do
      order = quoted_order!
      session_login!(owner)
      patch job_order_job_task_path(order, task1(order)),
            params: { step: "3", job_task: { job_task_options_attributes: [
              { job_option_id: JobOption.find_by!(name: "Polish").id, option_file: FilesTestHelper.mp4 }
            ] } }

      expect(flash[:alert]).to match(/Option file/i)
      expect(task1(order).job_task_options.first.option_file).not_to be_attached
      expect_not_sent_back(order)
    end

    it "an aborted task destroy is a normal error, not a 500" do
      order = quoted_order!
      allow_any_instance_of(JobTask).to receive(:destroy).and_return(false)
      session_login!(owner)
      delete job_order_job_task_path(order, order.job_tasks.find_by!(title: "Task #2"))

      expect(response).to redirect_to(job_order_path(order))
      expect(flash[:alert]).to be_present
      expect(order.reload.job_tasks.count).to eq(2)
      expect_not_sent_back(order)
    end
  end

  describe "a send-back that cannot be written" do
    def break_send_back!
      allow_any_instance_of(JobOrderStatus).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(JobOrderStatus.new))
    end

    it "wizard: says the order could not be sent back, reports it, commits nothing (not a task error)" do
      order = quoted_order!
      break_send_back!
      expect(Rails.error).to receive(:report)
        .with(an_instance_of(JobOrder::StatusRowInvalid), hash_including(handled: true))
      session_login!(owner)
      delete job_order_job_task_path(order, order.job_tasks.find_by!(title: "Task #2"))

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.send_back_failed"))
      expect(order.reload.job_tasks.count).to eq(2)
      expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
    end

    it "/pay: says the order could not be sent back, reports it, commits nothing (not 'try again later')" do
      order = quoted_order!
      task1(order).job_task_quote.update_column(:price, 5) # the invoice no longer matches
      break_send_back!
      expect(Rails.error).to receive(:report)
        .with(an_instance_of(JobOrder::StatusRowInvalid), hash_including(handled: true))

      get pay_job_orders_path, params: { token: order.pay_token }

      expect(response).to redirect_to(job_order_path(order.id))
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.pay_send_back_failed"))
      expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
      expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    end
  end

  # The actor of a /pay send-back (and of an emailed approval) is the order's owner, so an order without an owner
  # has no live links at all.
  it "refuses pay and approval links of an order without an owner" do
    order = quoted_order!
    pay_token = order.pay_token
    approval_token = order.approval_token
    order.update_column(:user_id, nil)

    expect(JobOrder.from_pay_token(order.reload.pay_token)).to be_nil
    expect(JobOrder.from_approval_token(order.approval_token)).to be_nil
    get pay_job_orders_path, params: { token: pay_token }
    expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.pay_magic_link_expired"))
    expect(approval_token).to be_present
  end
end
