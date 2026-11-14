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

  it "reads the statuses of the owner's orders in a constant number of queries on index" do
    expect_flat(job_orders_path, owner)
  end

  it "reads the statuses of all orders in a constant number of queries on admin" do
    expect_flat(admin_job_orders_path, admin)
  end

  describe "admin list flags" do
    let(:staff) { create(:user, :staff) }
    let(:expedited) { JobOption.create!(name: "Expedited Resin", fee: 2) }

    # One order of each kind: expedited with two owner messages after a staff reply, plain with a
    # staff reply last, and plain with one owner message.
    def flagged_orders!
      fast, answered, waiting = orders!(3, owner: owner)
      fast.job_tasks.create!(title: "Task #1").job_task_options.create!(job_option: expedited)
      fast.job_tasks.create!(title: "Task #2")
      message!(fast, owner, 4.hours.ago)
      message!(fast, staff, 3.hours.ago)
      message!(fast, owner, 2.hours.ago)
      message!(fast, owner, 1.hour.ago)
      message!(answered, owner, 2.hours.ago)
      message!(answered, staff, 1.hour.ago)
      message!(waiting, owner, 1.hour.ago)
      [fast, answered, waiting]
    end

    def message!(order, sender, at)
      ChatMessage.create!(job_order: order, sender: sender, message: "note", created_at: at)
    end

    def flags
      Nokogiri::HTML(response.body).css("tr[id^='job-order-row-']").to_h do |row|
        cells = row.css("td")
        [row["id"].delete_prefix("job-order-row-").to_i, [cells[0].text.squish, cells[1].text.squish]]
      end
    end

    it "marks expedited orders and counts the owner's unanswered messages in a number of queries that does not grow with the orders", :aggregate_failures do
      session_login!(admin)
      flagged_orders!
      get admin_job_orders_path # warm up (caches, constants)
      few = count_queries { get admin_job_orders_path }
      fast, answered, waiting = flagged_orders!
      get admin_job_orders_path # warm up again: making orders reseeds the statuses and clears their cache
      many = count_queries { get admin_job_orders_path }

      expect(many).to eq(few)
      expect(flags.values_at(fast.id, answered.id, waiting.id))
        .to eq([["Expedited", "2 unread messages"], ["", ""], ["", "1 unread messages"]])
    end
  end

  it "does not load the services of the orders on admin, which the list never shows" do
    session_login!(admin)
    orders!(2, owner: owner)
    sqls = []
    callback = ->(*, payload) { sqls << payload[:sql] if payload[:sql].include?("job_orders_services") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_job_orders_path }

    expect(response).to have_http_status(:ok)
    expect(sqls).to eq([])
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

  it "gives each submitted cell a machine-readable UTC timestamp whatever the language" do
    session_login!(admin)
    order = orders!(1, owner: owner).first
    get admin_job_orders_path, params: { locale: "fr" }

    expect(response).to have_http_status(:ok)
    cell = Nokogiri::HTML(response.body).at_css("td[data-sort='#{order.created_at.utc.iso8601}']")
    expect(cell.text.strip).to eq(I18n.l(order.created_at, format: :long, locale: :fr))
  end
end
