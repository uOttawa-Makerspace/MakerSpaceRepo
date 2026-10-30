# frozen_string_literal: true

require "rails_helper"

# JOB-03 follow-up: the draft fingerprint is canonical. It is built from stable
# keys and amounts only (task id, component, 2-decimal amount), sorted, so the
# order rows come back from the database in, and display titles (task titles,
# option names), cannot change it. The quote is loaded once per request (one
# query per table, no N+1) and reused for the fingerprint, the draft and the
# total.
RSpec.describe "Job order quote fingerprint", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/invoice" } }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
  end

  def shopify_ops
    shopify.calls.map { |c| c[:query][/\b(draftOrder\w+|getDraftOrder)\b/] }
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status.name }
  end

  # three quoted tasks, each with two quoted options, plus two order line items
  def completed_order!
    order = make_job_order!(owner: owner, status_key: :completed)
    options = [JobOption.create!(name: "Polish", fee: 1), JobOption.create!(name: "Sand", fee: 1)]
    3.times do |i|
      task = order.job_tasks.create!(title: "Task ##{i + 1}")
      task.build_job_task_quote(price: 10 + i, service_price: 2, service_quantity: 3).save!
      options.each_with_index { |o, j| task.job_task_quote.job_task_quote_options.create!(job_option: o, price: j + 1) }
    end
    order.job_quote_line_items.create!(description: "Rush", price: 2.5)
    order.job_quote_line_items.create!(description: "Setup", price: 1.25)
    order.reload
  end

  # sets an indexed column to `temp` and back, in two UPDATEs (`temp` points at a real row: these are foreign keys)
  def rewrite_row!(record, column, temp)
    original = record.public_send(column)
    record.class.where(id: record.id).update_all(column => temp)
    record.class.where(id: record.id).update_all(column => original)
  end

  def pay!(order)
    get pay_job_orders_path, params: { token: order.pay_token }
  end

  it "keeps serving the draft after rows are rewritten without a value change (row order is not part of it)" do
    order = completed_order!
    pay!(order)
    expect(order.reload.shopify_draft_order_id).to be_present

    # Changing an indexed column and back writes new row versions with new index entries (not a HOT update), so
    # these rows now come back last from a read without ORDER BY, by seq scan and by index scan alike.
    other = create(:job_order, user: owner)
    other_task = other.job_tasks.create!(title: "Other")
    other_quote = other_task.build_job_task_quote(price: 1).tap(&:save!)
    first_task = order.job_tasks.min_by(&:id)
    rewrite_row!(first_task, :job_order_id, other.id)
    rewrite_row!(first_task.job_task_quote, :job_task_id, other_task.id)
    rewrite_row!(first_task.job_task_quote.job_task_quote_options.min_by(&:id), :job_task_quote_id, other_quote.id)
    rewrite_row!(order.job_quote_line_items.min_by(&:id), :job_order_id, other.id)
    expect(order.job_tasks.reload.map(&:id)).not_to eq(order.job_tasks.map(&:id).sort) # the reorder took effect
    shopify.calls.clear

    pay!(order)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("https://pay.example/invoice")
    expect(shopify_ops).to eq(["getDraftOrder"])
    expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
  end

  it "keeps serving the draft after a JobOption is renamed (titles are not part of it)" do
    order = completed_order!
    pay!(order)
    JobOption.find_by!(name: "Polish").update!(name: "Polish (premium)")
    shopify.calls.clear

    pay!(order)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("https://pay.example/invoice")
    expect(shopify_ops).to eq(["getDraftOrder"])
    expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
  end

  it "builds the quote once per /pay: one query per quote table, whatever the number of tasks" do
    order = completed_order!
    pay!(order) # creates the draft
    tables = Hash.new(0)
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      %w[job_tasks job_task_quotes job_task_quote_options job_options job_quote_line_items].each do |table|
        tables[table] += 1 if payload[:sql].match?(/FROM "#{table}"/)
      end
    end
    begin
      pay!(order)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    expect(response.body).to include("https://pay.example/invoice")
    expect(tables).to eq("job_tasks" => 1, "job_task_quotes" => 1, "job_task_quote_options" => 1,
                         "job_options" => 1, "job_quote_line_items" => 1)
  end

  it "sends a draft built from the same snapshot it fingerprints, task lines in task-id order" do
    order = completed_order!
    pay!(order)

    sent = shopify.calls.find { |c| c[:query].include?("draftOrderCreate") }[:variables][:input][:lineItems]
    expect(sent.map { |l| l[:title] }).to eq(
      ["Task #1 Service Fee", "Task #1 Parts Fee", "Task #1 Polish", "Task #1 Sand",
       "Task #2 Service Fee", "Task #2 Parts Fee", "Task #2 Polish", "Task #2 Sand",
       "Task #3 Service Fee", "Task #3 Parts Fee", "Task #3 Polish", "Task #3 Sand", "Line Items Total"]
    )
    expect(order.reload.shopify_draft_order_fingerprint).to eq(JobOrder.find(order.id).quote_fingerprint)
  end
end
