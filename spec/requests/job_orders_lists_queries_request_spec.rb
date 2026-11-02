# frozen_string_literal: true

require "rails_helper"

# The order lists read each order's latest status from a preload (index, admin), and /pay reads it with one
# ORDER BY id DESC LIMIT 1 query instead of reloading the history.
RSpec.describe "Job order lists: status queries", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:admin) { create(:user, :admin) }
  let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/invoice" } }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
  end

  def status_selects
    sqls = []
    callback = ->(*, payload) { sqls << payload[:sql] if payload[:sql].match?(/\ASELECT .*FROM "?job_order_statuses"?[ )]/m) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    sqls
  end

  def orders!(count, owner:)
    Array.new(count) do
      make_job_order!(owner: owner, status_key: :staff_approval).tap do |o|
        o.job_order_statuses.create!(job_status: JobStatus.user_approval, user: owner)
      end
    end
  end

  # Statuses are read by the same number of queries whatever the number of orders.
  def expect_flat(path, user)
    session_login!(user)
    orders!(2, owner: owner)
    get path # warm up (caches, constants)
    few = status_selects { get path }
    orders!(4, owner: owner)
    many = status_selects { get path }

    expect(response).to have_http_status(:ok)
    expect(many.size).to eq(few.size)
  end

  it "reads the statuses of the owner's orders in a constant number of queries on index", skip_bullet: true do # other N+1s on these lists are pinned
    expect_flat(job_orders_path, owner)
  end

  it "reads the statuses of all orders in a constant number of queries on admin", skip_bullet: true do # other N+1s on these lists are pinned
    expect_flat(admin_job_orders_path, admin)
  end

  it "re-reads the latest status on /pay with one LIMIT 1 query, never the whole history" do
    order = make_job_order!(owner: owner, status_key: :completed)
    task = order.job_tasks.create!(title: "Task #1")
    task.build_job_task_quote(price: 29.99, service_price: 0, service_quantity: 0).save!

    selects = status_selects { get pay_job_orders_path, params: { token: order.reload.pay_token } }

    expect(response).to have_http_status(:ok)
    expect(selects).not_to be_empty
    expect(selects.reject { |q| q.match?(/LIMIT/i) }).to eq([])
  end
end
