# frozen_string_literal: true

require "rails_helper"

# JOB-04: a PAID / PICKED_UP order can never be re-quoted or declined, whether
# or not it has a Shopify draft and whether or not the prices change.
RSpec.describe "Quoting a paid job order (JOB-04)", type: :request do
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

  def quoted_order!(status_key, price: 29.99)
    order = make_job_order!(owner: owner, status_key: status_key)
    task = order.job_tasks.create!(title: "Task #1")
    task.build_job_task_quote(price: price, service_price: 0, service_quantity: 0).save!
    [order.reload, task]
  end

  def quote!(order, task, price, approved: "true")
    session_login!(staff)
    patch job_order_quote_path(order), params: { approved: approved, "job_task_quote_price_#{task.id}" => price.to_s,
                                                 job_order: { staff_comments: "" } }
  end

  # ------------------------------------------------------------------ JOB-04

  describe "re-quoting or declining a paid order (JOB-04)" do
    {
      "PAID, no draft, new price" => [:paid, false, 55, "true"],
      "PAID, draft, same price" => [:paid, true, 29.99, "true"],
      "PICKED_UP, no draft, same price" => [:picked_up, false, 29.99, "true"],
      "PAID, decline" => [:paid, false, 29.99, "false"],
      "PICKED_UP, decline" => [:picked_up, true, 29.99, "false"]
    }.each do |label, (status_key, draft, price, approved)|
      it "is refused before any write (#{label})" do
        order, task = quoted_order!(status_key)
        order.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/9001") if draft
        before = status_names(order)
        quote!(order, task, price, approved: approved)

        expect(response).to redirect_to(job_order_path(order.id))
        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.quote_refused_paid"))
        expect(status_names(order)).to eq(before)
        expect(order.reload.total_price).to eq(BigDecimal("29.99"))
        expect(shopify.calls).to be_empty
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end
  end

  describe "a normal quote" do
    it "writes no 'Unpermitted parameters' log line for its other keys" do
      order, task = quoted_order!(:user_approval)
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      Rails.logger.broadcast_to(logger)
      begin
          session_login!(staff)
        patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => "40",
                                                     job_order: { staff_comments: "see notes", comments: "x" } }
      ensure
        Rails.logger.stop_broadcasting_to(logger)
      end

      expect(order.reload.total_price).to eq(BigDecimal("40"))
      expect(order.staff_comments).to eq("see notes")
      expect(io.string).not_to include("Unpermitted parameter")
    end
  end
end
