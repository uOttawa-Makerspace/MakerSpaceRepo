# frozen_string_literal: true

require "rails_helper"

# A quote with a price that is negative or not a number is refused with a message and writes nothing; it never
# answers with a server error.
RSpec.describe "Job order quote input", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
    session_login!(staff)
  end

  let!(:order) { make_job_order!(owner: owner, status_key: :staff_approval) }
  let!(:task) { order.job_tasks.create!(title: "Task #1") }

  def quote(extra = {})
    patch job_order_quote_path(order), params: {
      approved: "true",
      "job_task_quote_price_#{task.id}" => "10",
      "task_#{task.id}_service_qty" => "1",
      "task_#{task.id}_service_price" => "2"
    }.merge(extra)
  end

  def status_names
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  {
    "a negative price" => { "job_task_quote_price_%d" => "-5" },
    "a price that is not a number" => { "job_task_quote_price_%d" => "abc" },
    "a negative service price" => { "task_%d_service_price" => "-1" },
    "a negative service quantity" => { "task_%d_service_qty" => "-2" }
  }.each do |label, change|
    it "refuses #{label} with a message and records no quote" do
      key, value = change.first
      quote(format(key, task.id) => value)

      expect(response).to redirect_to(job_order_path(order.id))
      expect(flash[:alert]).to start_with(I18n.t("errors.job_orders.quote_invalid"))
      expect(task.reload.job_task_quote).to be_nil
      expect(status_names).to eq(["Waiting for Staff Approval"])
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it "quotes without a job_order param" do
    quote
    expect(response).to redirect_to(job_order_path(order.id))
    expect(status_names).to end_with("Waiting for User Approval")
  end
end
