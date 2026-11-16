# frozen_string_literal: true

require "rails_helper"

# A task with a service line (a job service) must have a service price before its
# quote is sent, reminded, approved or paid. A price of 0 is a price (a free service); a blank one is refused with a
# message naming the task, and no amount, status, mail or Shopify call changes.
RSpec.describe "Job order quotes with a missing service price", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/invoice" } }
  let(:job_type) { create(:job_type) }
  let(:service) { create(:job_service, job_service_group: create(:job_service_group, job_type: job_type)) }

  before do
    seed_job_statuses!
    seed_job_order_message!
    ActionMailer::Base.deliveries.clear
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  def refusal(task_title = "Laser job")
    I18n.t("job_orders.alerts.status_change.service_price_missing", tasks: task_title)
  end

  # an order whose one task has the service and, when `service_price` is given, a quote row (nil = a blank price)
  def order_at!(status_key, service_price:, title: "Laser job")
    order = make_job_order!(owner: owner, status_key: status_key)
    task = order.job_tasks.create!(title: title, job_type: job_type, job_service: service)
    task.build_job_task_quote(price: 10, service_price: service_price, service_quantity: 2).save!
    order.reload
  end

  def quote_params(task, service_price:)
    { approved: "true", "job_task_quote_price_#{task.id}" => "10", "task_#{task.id}_service_qty" => "2",
      "task_#{task.id}_service_price" => service_price }
  end

  describe "PATCH quote (staff)" do
    before { session_login!(staff) }

    it "refuses a blank service price, naming the task, and changes nothing" do
      order = make_job_order!(owner: owner, status_key: :staff_approval)
      task = order.job_tasks.create!(title: "Laser job", job_type: job_type, job_service: service)

      expect { patch_quote order, quote_params(task, service_price: "") }
        .not_to(change { ActionMailer::Base.deliveries.size })

      expect(flash[:alert]).to eq(refusal)
      expect(status_names(order)).to eq(["Waiting for Staff Approval"])
      expect(task.reload.job_task_quote).to be_nil
    end

    it "keeps the earlier quote's amounts when a re-quote is refused" do
      order = order_at!(:user_approval, service_price: 3)
      task = order.job_tasks.first

      patch_quote order, quote_params(task, service_price: "").merge("job_task_quote_price_#{task.id}" => "99")

      expect(flash[:alert]).to eq(refusal)
      expect(task.reload.job_task_quote.attributes.slice("price", "service_price").values).to eq([10, 3])
      expect(status_names(order)).to eq(["Waiting for User Approval"])
    end

    it "accepts a service price of 0 (a free service) and stores it as 0" do
      order = make_job_order!(owner: owner, status_key: :staff_approval)
      task = order.job_tasks.create!(title: "Laser job", job_type: job_type, job_service: service)

      patch_quote order, quote_params(task, service_price: "0")

      expect(flash[:alert]).to be_nil
      expect(task.reload.job_task_quote.service_price).to eq(0)
      expect(status_names(order).last).to eq("Waiting for User Approval")
    end

    it "does not ask for a price when the task has no service line" do
      order = make_job_order!(owner: owner, status_key: :staff_approval)
      task = order.job_tasks.create!(title: "Design")

      patch_quote order, { approved: "true", "job_task_quote_price_#{task.id}" => "20" }

      expect(flash[:alert]).to be_nil
      expect(task.reload.job_task_quote.service_price).to be_nil
      expect(status_names(order).last).to eq("Waiting for User Approval")
    end
  end

  describe "PATCH resend_quote_email (staff)" do
    it "refuses a quote whose service price is missing, and sends nothing" do
      order = order_at!(:user_approval, service_price: nil)
      session_login!(staff)

      expect { patch job_order_resend_quote_email_path(order) }.not_to(change { ActionMailer::Base.deliveries.size })

      expect(flash[:alert]).to eq(refusal)
      expect(status_names(order)).to eq(["Waiting for User Approval"])
    end

    it "still reminds when the service price is 0" do
      order = order_at!(:user_approval, service_price: 0)
      session_login!(staff)

      expect { patch job_order_resend_quote_email_path(order) }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(status_names(order).last).to eq("Sent a Quote Reminder")
    end
  end

  describe "the customer's approval" do
    it "is refused through the magic link while the service price is missing" do
      order = order_at!(:user_approval, service_price: nil)

      patch user_magic_approval_confirmation_job_orders_path, params: { token: order.approval_token, approved: "true" }

      expect(status_names(order)).to eq(["Waiting for User Approval"])
    end

    it "is refused when the signed-in customer approves" do
      order = order_at!(:user_approval, service_price: nil)
      session_login!(owner)

      patch job_order_user_approval_path(order), params: { approved: "true" }

      expect(flash[:alert]).to eq(refusal)
      expect(status_names(order)).to eq(["Waiting for User Approval"])
    end

    it "goes through with a price of 0" do
      order = order_at!(:user_approval, service_price: 0)

      patch user_magic_approval_confirmation_job_orders_path, params: { token: order.approval_token, approved: "true" }

      expect(status_names(order).last).to eq("Waiting to be Processed")
    end
  end

  describe "marking the order completed (the payment-link mail)" do
    it "is refused while the service price is missing" do
      order = order_at!(:being_processed, service_price: nil)
      session_login!(staff)

      expect { patch job_order_processed_path(order), params: { completed: "true", send_email: "true" } }
        .not_to(change { ActionMailer::Base.deliveries.size })

      expect(flash[:alert]).to eq(refusal)
      expect(status_names(order)).to eq(["Currently being Processed"])
    end
  end

  describe "GET pay" do
    it "creates no payment link while the service price is missing" do
      order = order_at!(:completed, service_price: nil)

      get pay_job_orders_path, params: { token: order.pay_token }

      expect(response).to redirect_to(job_order_path(order))
      expect(flash[:alert]).to eq(refusal)
      expect(shopify.calls).to be_empty
      expect(order.reload.shopify_draft_order_id).to be_nil
      expect(status_names(order)).to eq(["Completed (Waiting for Payment)"])
    end

    it "names every unpriced task" do
      order = order_at!(:completed, service_price: nil)
      order.job_tasks.create!(title: "Router job", job_type: job_type, job_service: service)

      get pay_job_orders_path, params: { token: order.pay_token }

      expect(flash[:alert]).to eq(refusal("Laser job and Router job"))
    end

    it "serves the link for a price of 0" do
      order = order_at!(:completed, service_price: 0)

      get pay_job_orders_path, params: { token: order.pay_token }

      expect(response.body).to include("https://pay.example/invoice")
    end
  end
end
