# frozen_string_literal: true

require "rails_helper"

# What the staff quote form stores: each task's price, service quantity and price, option prices and staff files,
# the order's line items and the staff comment. Every stored row and amount is asserted exactly, for each
# combination of present, blank and invalid values.
RSpec.describe "Job order quote params", type: :request do
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

  def quote(params)
    patch_quote(order, { approved: "true" }.merge(params))
  end

  def stored_quote(for_task = task)
    q = for_task.reload.job_task_quote
    q && [q.price, q.service_quantity, q.service_price]
  end

  def stored_options(for_task = task)
    for_task.reload.job_task_quote.job_task_quote_options.order(:job_option_id).pluck(:job_option_id, :price)
  end

  def stored_line_items
    order.reload.job_quote_line_items.order(:id).pluck(:description, :price)
  end

  def status_names
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  def quoted_notice
    I18n.t("job_orders.alerts.updated_job_status_to_x", status: JobStatus.user_approval.t_name)
  end

  def expect_quoted
    expect(response).to redirect_to(job_order_path(order.id))
    expect(flash[:notice]).to eq(quoted_notice)
    expect(status_names).to eq(["Waiting for Staff Approval", "Waiting for User Approval"])
  end

  def expect_refused_invalid
    expect(response).to redirect_to(job_order_path(order.id))
    expect(flash[:alert]).to start_with(I18n.t("errors.job_orders.quote_invalid"))
    expect_nothing_sent
  end

  def expect_nothing_sent
    expect(status_names).to eq(["Waiting for Staff Approval"])
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  describe "task price, service quantity and service price" do
    it "stores all three as given, rounded to the column scale" do
      quote("job_task_quote_price_#{task.id}" => "12.345", "task_#{task.id}_service_qty" => "1.23456",
            "task_#{task.id}_service_price" => "2.5")
      expect_quoted
      expect(stored_quote).to eq([BigDecimal("12.35"), BigDecimal("1.2346"), BigDecimal("2.5")])
    end

    it "stores a blank price and quantity as 0 and a blank service price as nil" do
      quote("job_task_quote_price_#{task.id}" => "", "task_#{task.id}_service_qty" => "",
            "task_#{task.id}_service_price" => "")
      expect_quoted
      expect(stored_quote).to eq([BigDecimal("0"), BigDecimal("0"), nil])
    end

    it "stores missing keys the same as blank ones" do
      quote({})
      expect_quoted
      expect(stored_quote).to eq([BigDecimal("0"), BigDecimal("0"), nil])
    end

    it "stores a service price of 0 as 0" do
      quote("job_task_quote_price_#{task.id}" => "5", "task_#{task.id}_service_qty" => "3",
            "task_#{task.id}_service_price" => "0")
      expect_quoted
      expect(stored_quote).to eq([BigDecimal("5"), BigDecimal("3"), BigDecimal("0")])
    end

    it "updates the task's existing quote row instead of adding one" do
      existing = task.create_job_task_quote!(price: 1, service_quantity: 1, service_price: 1)
      quote("job_task_quote_price_#{task.id}" => "7", "task_#{task.id}_service_qty" => "2",
            "task_#{task.id}_service_price" => "4")
      expect_quoted
      expect(JobTaskQuote.where(job_task_id: task.id).pluck(:id)).to eq([existing.id])
      expect(stored_quote).to eq([BigDecimal("7"), BigDecimal("2"), BigDecimal("4")])
    end

    it "overwrites an existing quote's values with the blank defaults" do
      task.create_job_task_quote!(price: 9, service_quantity: 2, service_price: 3)
      quote({})
      expect_quoted
      expect(stored_quote).to eq([BigDecimal("0"), BigDecimal("0"), nil])
    end

    it "quotes every task of the order, each from its own keys" do
      second = order.job_tasks.create!(title: "Task #2")
      quote("job_task_quote_price_#{task.id}" => "10", "job_task_quote_price_#{second.id}" => "20",
            "task_#{second.id}_service_qty" => "4", "task_#{second.id}_service_price" => "1.5")
      expect_quoted
      expect(stored_quote(task)).to eq([BigDecimal("10"), BigDecimal("0"), nil])
      expect(stored_quote(second)).to eq([BigDecimal("20"), BigDecimal("4"), BigDecimal("1.5")])
    end

    it "refuses a quote when a later task's price is invalid, and writes nothing for the earlier task" do
      second = order.job_tasks.create!(title: "Task #2")
      quote("job_task_quote_price_#{task.id}" => "10", "job_task_quote_price_#{second.id}" => "-1")
      expect_refused_invalid
      expect(stored_quote(task)).to be_nil
      expect(stored_quote(second)).to be_nil
    end

    it "reads the tasks' quote rows in as many queries for three tasks as for one" do
      option = create(:job_option)
      reads = ->(job_order) { selects_on("job_task_quotes") { patch_quote(job_order, { approved: "true" }) }.size }
      orders = [1, 3].map do |count|
        job_order = make_job_order!(owner: owner, status_key: :staff_approval)
        count.times { |i| job_order.job_tasks.create!(title: "Task #{i}").job_task_options.create!(job_option: option) }
        job_order
      end

      expect(reads.call(orders[1])).to eq(reads.call(orders[0]))
      expect(orders.map { |o| o.job_tasks.map { |t| t.reload.job_task_quote&.price } }).to eq([[0], [0, 0, 0]])
    end

    it "refuses a task with a job service but no service price, with the missing service message" do
      job_type = JobType.find_by!(name: "3D Print")
      group = create(:job_service_group, job_type: job_type)
      service = create(:job_service, job_service_group: group)
      task.update!(job_type: job_type, job_service: service)

      quote("job_task_quote_price_#{task.id}" => "10", "task_#{task.id}_service_qty" => "1")

      expect(response).to redirect_to(job_order_path(order.id))
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.status_change.service_price_missing", tasks: "Task #1"))
      expect(status_names).to eq(["Waiting for Staff Approval"])
      expect(stored_quote).to be_nil
    end
  end

  describe "option prices" do
    let(:options) { create_list(:job_option, 3).sort_by(&:id) }

    before { options.each { |o| task.job_task_options.create!(job_option: o) } }

    def option_key(option)
      "task_#{task.id}_option_price_#{option.id}"
    end

    it "stores a price for each option given one and none for a blank or missing one" do
      quote("job_task_quote_price_#{task.id}" => "10", option_key(options[0]) => "3.333",
            option_key(options[1]) => "")
      expect_quoted
      expect(stored_options).to eq([[options[0].id, BigDecimal("3.33")]])
    end

    it "updates an existing option price row instead of adding one, and keeps one left blank" do
      existing = task.create_job_task_quote!(price: 1)
      kept = existing.job_task_quote_options.create!(job_option: options[0], price: 1)
      changed = existing.job_task_quote_options.create!(job_option: options[1], price: 1)

      quote("job_task_quote_price_#{task.id}" => "10", option_key(options[1]) => "6", option_key(options[2]) => "0")

      expect_quoted
      expect(stored_options).to eq([[options[0].id, BigDecimal("1")], [options[1].id, BigDecimal("6")],
                                    [options[2].id, BigDecimal("0")]])
      expect(JobTaskQuoteOption.where(id: [kept.id, changed.id]).count).to eq(2)
    end

    it "ignores a price for an option the task does not have" do
      other = create(:job_option)
      quote("job_task_quote_price_#{task.id}" => "10", "task_#{task.id}_option_price_#{other.id}" => "4")
      expect_quoted
      expect(stored_options).to eq([])
    end

    it "refuses an invalid option price and writes nothing" do
      quote("job_task_quote_price_#{task.id}" => "10", option_key(options[0]) => "2", option_key(options[1]) => "-3")
      expect_refused_invalid
      expect(stored_quote).to be_nil
      expect(JobTaskQuoteOption.count).to eq(0)
    end

    it "refuses an option price that is not a number" do
      quote("job_task_quote_price_#{task.id}" => "10", option_key(options[0]) => "abc")
      expect_refused_invalid
      expect(JobTaskQuoteOption.count).to eq(0)
    end
  end

  describe "staff files" do
    it "attaches each uploaded staff file to its task" do
      quote("job_task_quote_price_#{task.id}" => "10",
            "task_#{task.id}_staff_files" => [FilesTestHelper.stl, FilesTestHelper.pdf])
      expect_quoted
      expect(task.reload.staff_files.map { |f| f.blob.filename.to_s }.sort).to eq(["#{order.id}_RepoFile1.pdf",
                                                                                  "#{order.id}_test.stl"])
    end

    it "attaches nothing when no staff files are sent" do
      quote("job_task_quote_price_#{task.id}" => "10")
      expect_quoted
      expect(task.reload.staff_files).not_to be_attached
    end

    it "attaches nothing when a refused quote sent staff files" do
      quote("job_task_quote_price_#{task.id}" => "-1", "task_#{task.id}_staff_files" => [FilesTestHelper.stl])
      expect_refused_invalid
      expect(task.reload.staff_files).not_to be_attached
    end
  end

  describe "line items" do
    before do
      order.job_quote_line_items.create!(description: "Old", price: 9)
    end

    def items(*rows)
      rows = rows.each_with_index.to_h { |(desc, price), i| [i.to_s, { description: desc, price: price }] }
      { job_quote_line_items: rows }
    end

    it "keeps the existing line items when the form sends none" do
      quote("job_task_quote_price_#{task.id}" => "10")
      expect_quoted
      expect(stored_line_items).to eq([["Old", BigDecimal("9")]])
    end

    it "replaces the line items with the sent ones, stripped, in the sent order" do
      quote({ "job_task_quote_price_#{task.id}" => "10" }.merge(items([" Rush ", " 2.505 "], ["Setup", "1"])))
      expect_quoted
      expect(stored_line_items).to eq([["Rush", BigDecimal("2.51")], ["Setup", BigDecimal("1")]])
    end

    it "skips a row with a blank description and price and stores a blank price as 0" do
      quote({ "job_task_quote_price_#{task.id}" => "10" }.merge(items(["  ", " "], ["Free", ""])))
      expect_quoted
      expect(stored_line_items).to eq([["Free", BigDecimal("0")]])
    end

    it "removes every line item when each sent row is blank" do
      quote({ "job_task_quote_price_#{task.id}" => "10" }.merge(items(["", ""])))
      expect_quoted
      expect(stored_line_items).to eq([])
    end

    it "refuses a row with a price but no description and keeps the old line items" do
      quote({ "job_task_quote_price_#{task.id}" => "10" }.merge(items(["Ok", "1"], ["", "3"])))
      expect_refused_invalid
      expect(stored_line_items).to eq([["Old", BigDecimal("9")]])
    end

    it "refuses a negative line item price and keeps the old line items" do
      quote({ "job_task_quote_price_#{task.id}" => "10" }.merge(items(["Discount", "-5"])))
      expect_refused_invalid
      expect(stored_line_items).to eq([["Old", BigDecimal("9")]])
    end
  end

  describe "staff comments" do
    before { order.update!(staff_comments: "Before") }

    it "stores a staff comment that is a non-blank string" do
      quote("job_task_quote_price_#{task.id}" => "10", job_order: { staff_comments: "Use PLA" })
      expect_quoted
      expect(order.reload.staff_comments).to eq("Use PLA")
    end

    it "keeps the comment when the sent one is blank" do
      quote("job_task_quote_price_#{task.id}" => "10", job_order: { staff_comments: "" })
      expect_quoted
      expect(order.reload.staff_comments).to eq("Before")
    end

    it "keeps the comment when it is not a string" do
      quote("job_task_quote_price_#{task.id}" => "10", job_order: { staff_comments: %w[a b] })
      expect_quoted
      expect(order.reload.staff_comments).to eq("Before")
    end

    it "keeps the comment when job_order is not a hash" do
      quote("job_task_quote_price_#{task.id}" => "10", job_order: "text")
      expect_quoted
      expect(order.reload.staff_comments).to eq("Before")
    end

    it "keeps the comment when job_order has no staff_comments" do
      quote("job_task_quote_price_#{task.id}" => "10", job_order: { other: "x" })
      expect_quoted
      expect(order.reload.staff_comments).to eq("Before")
    end
  end
end
