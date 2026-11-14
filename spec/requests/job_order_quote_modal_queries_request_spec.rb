# frozen_string_literal: true

require "rails_helper"

# The quote modal on a job order's page (staff only) shows, for each task, its job type and service, the base fee,
# the service quantity and price, and a price for each of the task's options, taken from the saved quote or else from
# the defaults. Those are read once for the whole order, so the number of queries does not grow with the tasks. The
# counts start at two tasks: with one, the query cache can hide a repeated read.
RSpec.describe "Job order quote modal: queries", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:order) { make_job_order!(owner: owner, status_key: :staff_approval) }
  let(:job_type) { JobType.find_by!(name: "3D Print") }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    job_type.update!(service_fee: 4.5)
  end

  # A task with its own service and two options of its own; every other one is quoted, with a price for its first
  # option only. No two tasks share a row, so no read of one is answered from the query cache.
  def tasks!(count)
    Array.new(count) do |i|
      group = create(:job_service_group, job_type: job_type)
      service = create(:job_service, job_service_group: group, unit: "gram", internal_price: 0.25, external_price: 0.5)
      task = order.job_tasks.create!(title: "Print #{order.job_tasks.count + 1}", job_type: job_type, job_service: service)
      options = Array.new(2) { |n| task.job_task_options.create!(job_option: JobOption.create!(name: "Option #{task.id}-#{n}", fee: 1 + n)) }
      quote!(task, options.first) if i.even?
      task
    end
  end

  def quote!(task, option)
    quote = task.create_job_task_quote!(price: 12, service_price: 0.75, service_quantity: 3)
    quote.job_task_quote_options.create!(job_option: option.job_option, price: 6.5)
  end

  def modal
    Nokogiri::HTML(response.body).at_css("#quote-modal-rendered")
  end

  def queries_for(path)
    get path
    count_queries { get path }
  end

  # The task cards' headings, labels and inputs (name and value), in page order.
  def task_fields
    modal.css(".card").reject { |card| card.at_css("#line-items-container") }.flat_map do |card|
      card.css("h5, label, input").map { |node| node.name == "input" ? [node["name"], node["value"]] : node.text.squish }
    end
  end

  def card_fields(task, base:, qty:, service:, options:)
    service_name = "#{task.job_service.name} (#{task.job_service.job_service_group.name})"
    ["#{task.title} 3D Print - #{service_name}", "Base Fee (CAD)", ["job_task_quote_price_#{task.id}", base],
     "Number of gram", ["task_#{task.id}_service_qty", qty], "Price per gram (CAD)", ["task_#{task.id}_service_price", service],
     *task.job_task_options.order(:id).zip(options).flat_map do |option, price|
       ["#{option.job_option.name} (CAD)", ["task_#{task.id}_option_price_#{option.job_option_id}", price]]
     end,
     "Staff Files (GCode, PDF, etc.)", ["task_#{task.id}_staff_files[]", nil]]
  end

  it "shows each task's service, base fee and option prices from the quote, or the defaults without one" do
    quoted, plain = tasks!(2)
    session_login!(staff)

    get job_order_path(order)

    expect(response).to have_http_status(:ok)
    expect(task_fields).to eq(card_fields(quoted, base: "12.0", qty: "3.0", service: "0.75", options: %w[6.5 2.00]) +
                              card_fields(plain, base: "4.50", qty: "1.0", service: "0.50", options: %w[1.00 2.00]))
  end

  it "runs the same number of queries for two tasks as for five" do
    session_login!(staff)
    tasks!(2)
    two = queries_for(job_order_path(order))
    tasks!(3)
    five = queries_for(job_order_path(order))

    expect(response).to have_http_status(:ok)
    expect(modal.css(".card-header h5").size).to eq(6) # five tasks and the line items card
    expect(five).to eq(two)
  end
end
