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

  describe "owner list unread messages" do
    let(:staff) { create(:user, :staff) }

    def message!(order, sender, read: false)
      ChatMessage.create!(job_order: order, sender: sender, message: "note", is_read: read)
    end

    # Per order, the unread badge's count, or nil without one.
    def unread_badges
      Nokogiri::HTML(response.body).css("tr[id^='job-order-row-']").to_h do |row|
        [row["id"].delete_prefix("job-order-row-").to_i, row.at_css("td .badge")&.text&.squish]
      end
    end

    # Each order with two unread staff messages, one read staff message and one of the owner's own.
    def chatty_orders!(count)
      orders!(count, owner: owner).each do |order|
        2.times { message!(order, staff) }
        message!(order, staff, read: true)
        message!(order, owner)
      end
    end

    it "badges each order with the messages from others the owner has not read" do
      session_login!(owner)
      read_all, unread = orders!(2, owner: owner)
      message!(read_all, staff, read: true)
      message!(read_all, owner)
      2.times { message!(unread, staff) }

      get job_orders_path

      expect(unread_badges).to eq(read_all.id => nil, unread.id => "2 unread messages")
    end

    it "counts the unread messages in a number of queries that does not grow with the orders" do
      session_login!(owner)
      chatty_orders!(2)
      get job_orders_path # warm up (caches, constants)
      few = count_queries { get job_orders_path }
      chatty_orders!(3)
      get job_orders_path # warm up again: making orders reseeds the statuses and clears their cache
      many = count_queries { get job_orders_path }

      expect(unread_badges.values).to eq(["2 unread messages"] * 5)
      expect(many).to eq(few)
    end
  end

  describe "settings option list" do
    let(:staff) { create(:user, :staff) }

    # Each option of its own with the job types it applies to: every other one applies to two, the rest to none.
    def options!(count)
      types = JobType.order(:id).first(2)
      Array.new(count) do |i|
        JobOption.create!(name: "Setting option #{JobOption.count}", fee: 3, job_types: i.even? ? types : [])
      end
    end

    # Per option row, its name and the job types it applies to.
    def option_rows
      table = Nokogiri::HTML(response.body).css("table.notDataTable").last
      table.css("tbody tr").map { |row| row.css("td").first(3).map { |td| td.text.squish } }.map { |name, _, types| [name, types] }
    end

    it "shows each option with the job types it applies to, or that it is not assigned" do
      session_login!(staff)
      options!(2)

      get settings_job_orders_path

      expect(response).to have_http_status(:ok)
      expect(option_rows).to eq([["Setting option 0", "3D Print Laser Cut"], ["Setting option 1", "Not assigned"]])
    end

    it "reads the options' job types in a number of queries that does not grow with the options" do
      session_login!(staff)
      options!(2)
      get settings_job_orders_path # warm up (caches, constants)
      few = count_queries { get settings_job_orders_path }
      options!(3)
      many = count_queries { get settings_job_orders_path }

      expect(option_rows.size).to eq(5)
      expect(many).to eq(few)
    end
  end

  describe "settings service groups" do
    let(:staff) { create(:user, :staff) }

    # Each group with two services, on the job types in turn.
    def groups!(count)
      types = JobType.order(:id).to_a
      Array.new(count) do |i|
        group = JobServiceGroup.create!(name: "Group #{JobServiceGroup.count}", job_type: types[i % types.size])
        2.times { |n| JobService.create!(name: "#{group.name} service #{n}", job_service_group: group) }
        group
      end
    end

    # Per job type card, its name and each group's name with its service names (or "None yet").
    def group_rows
      Nokogiri::HTML(response.body).css(".card.shadow-sm").filter_map do |card|
        groups = card.css("[id^='accordion-'] > .accordion-item").map do |item|
          services = item.css(".service-accordion .accordion-header .fw-semibold").map { |s| s.text.squish }
          [item.at_css(".accordion-header .fw-bold").text.squish, services.presence || item.at_css(".service-accordion").text.squish]
        end
        [card.at_css("h4").text.squish, groups] if card.at_css("h4")
      end
    end

    it "lists each job type's groups in creation order with their services, leaving out deleted and user-made ones" do
      session_login!(staff)
      print_type, laser_type = JobType.order(:id).first(2)
      second = JobServiceGroup.create!(name: "B group", job_type: print_type)
      first_laser = JobServiceGroup.create!(name: "Laser group", job_type: laser_type)
      third = JobServiceGroup.create!(name: "A group", job_type: print_type)
      JobServiceGroup.create!(name: "Gone group", job_type: print_type, is_deleted: true)
      JobService.create!(name: "Z service", job_service_group: second)
      JobService.create!(name: "Y service", job_service_group: second)
      JobService.create!(name: "Deleted service", job_service_group: second, is_deleted: true)
      JobService.create!(name: "Made by a user", job_service_group: second, user_created: true)
      JobService.create!(name: "Cutting", job_service_group: first_laser)

      get settings_job_orders_path

      expect(response).to have_http_status(:ok)
      rows = group_rows.to_h
      expect(rows[print_type.name]).to eq([["B group", ["Z service", "Y service"]], [third.name, "None yet"]])
      expect(rows[laser_type.name]).to eq([["Laser group", ["Cutting"]]])
      expect(rows.except(print_type.name, laser_type.name).values).to all(eq([]))
    end

    it "reads the groups and their services in a number of queries that does not grow with the groups" do
      session_login!(staff)
      groups!(2)
      get settings_job_orders_path # warm up (caches, constants)
      few = count_queries { get settings_job_orders_path }
      groups!(3)
      many = count_queries { get settings_job_orders_path }

      expect(group_rows.sum { |_, groups| groups.size }).to eq(5)
      expect(many).to eq(few)
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
