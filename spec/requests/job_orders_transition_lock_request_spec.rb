# frozen_string_literal: true

require "rails_helper"

# Every status transition reads the status (and, for the emailed approve link,
# the token) under the same job_orders row lock as the quote and the owner
# change, so a re-quote, a customer approval and an owner change cannot
# interleave. A quote reminder is only sent while the customer has a live quote.
RSpec.describe "Job order status transitions under the row lock", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status.name }
  end

  def quoted_order!(status_key, price: 29.99)
    order = make_job_order!(owner: owner, status_key: status_key)
    task = order.job_tasks.create!(title: "Task #1")
    task.build_job_task_quote(price: price, service_price: 0, service_quantity: 0).save!
    [order.reload, task]
  end

  # ------------------------------------------------------- transitions locked

  describe "status transitions read the status under the row lock" do
    # runs `side_effect` once, right before this request's lock is granted
    def before_lock(&side_effect)
      done = false
      allow_any_instance_of(JobOrder).to receive(:lock!).and_wrap_original do |m, *args|
        unless done
          done = true
          side_effect.call
        end
        m.call(*args)
      end
    end

    it "refuses an emailed approval when a re-quote committed between the token check and the lock" do
      order, = quoted_order!(:user_approval)
      old_token = order.approval_token
      before_lock { order.job_order_statuses.create!(job_status: JobStatus.user_approval, user: staff) }

      patch user_magic_approval_confirmation_job_orders_path, params: { token: old_token, approved: "true" }

      expect(status_names(order).last).to eq("Waiting for User Approval")
      expect(status_names(order)).not_to include("Waiting to be Processed")
    end

    it "refuses an emailed approval when an owner change committed between the token check and the lock" do
      order, = quoted_order!(:user_approval)
      token = order.approval_token
      before_lock { order.job_order_statuses.create!(job_status: JobStatus.staff_approval, user: owner, reason: "owner_change") }

      patch user_magic_approval_confirmation_job_orders_path, params: { token: token, approved: "true" }

      expect(status_names(order).last).to eq("Waiting for Staff Approval")
    end

    it "refuses a signed-in approval when an owner change committed just before the lock" do
      order, = quoted_order!(:user_approval)
      session_login!(owner)
      before_lock { order.job_order_statuses.create!(job_status: JobStatus.staff_approval, user: owner, reason: "owner_change") }

      patch job_order_user_approval_path(order), params: { approved: "true" }

      expect(status_names(order).last).to eq("Waiting for Staff Approval")
      expect(ActionMailer::Base.deliveries).to be_empty
    end


    it "only sends a quote reminder while the order is waiting for the customer" do
      order, = quoted_order!(:staff_approval)
      session_login!(staff)
      patch job_order_resend_quote_email_path(order)

      expect(status_names(order).last).to eq("Waiting for Staff Approval")
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
