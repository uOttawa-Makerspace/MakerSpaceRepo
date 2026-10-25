# frozen_string_literal: true

require "rails_helper"

# Browser-level characterization for the Job Orders public entry flow so a
# later refactor can prove no change in look & feel:
#
#   landing (/job_orders/landing)
#     → "Start a Job Order" → /job_orders/new (What kind of project…?)
#     → "Start Production" submit → /job_orders/:id/task/:t/edit?step=1 wizard
#
# Reference rows are seeded at the example level (JobStatus, JobTypes, the
# "processed" JobOrderMessage) — mirroring what any deployed DB looks like,
# because JobStatus resolves its boot constants once when the class loads.
RSpec.describe "Job Orders browser flow", type: :system do
  let(:user) { create(:user, :regular_user) }

  before do
    seed_job_statuses!
    seed_job_types!
    seed_job_order_message!
  end

  it "keeps the global navbar on the public landing page" do
    visit landing_job_orders_path
    expect(page).to have_css("nav.navbar")
    expect(page).to have_content("From Concept to Creation")
    expect(page).to have_link("Start a Job Order", href: new_job_order_path)
    expect(page).to have_link("View My Orders", href: job_orders_path)
  end

  it "guides the Ready-to-Make choice from landing to wizard step 1" do
    log_in_as(user)
    visit landing_job_orders_path

    click_link "Start a Job Order"
    expect(page).to have_content("What kind of project are you starting?")
    expect(page).to have_content("Ready to Make")
    expect(page).to have_content("Need Design Help")

    click_button "Start Production"

    # have_current_path waits for the navigation (page.current_path does not)
    expect(page).to have_current_path(%r{\A/job_orders/\d+/task/\d+/edit\z}, ignore_query: true)
    expect(page.current_url).to end_with("step=1")
    expect(page).to have_css("nav.navbar") # shell intact inside the wizard
    expect(page).to have_content("New Job Task (Step 1/4)")
    expect(page).to have_content("Job Type (required)*")
    expect(page).to have_button("Next Step")

    order = JobOrder.order(:id).last
    expect(order.user).to eq(user)
    expect(order.is_deleted).to be(false)
    # WART-PIN: the "Start Production" button's inline onclick JS is broken in
    # the shipped HTML — the ENB attribute quotes arrive un-escaped
    # (&#39; without the needed backslashes), so the handler raises
    # SyntaxError and the hidden job_type_id stays "" → the order is created
    # with a NULL job_type (typeless).
    expect(order.job_type_id).to be_nil
    expect(order.job_type).to be_nil
    expect(order.job_tasks.first.title).to eq("Task #1")
    expect(order.job_tasks.first.job_type).to be_nil
  end

  it "routes the Need-Design-Help choice straight into the design service step" do
    log_in_as(user)
    visit landing_job_orders_path
    click_link "Start a Job Order"

    click_button "Get Design Help"

    # Wait for the redirect to finish before reading the DB: the click returns
    # before the server has created the order (flaky under parallel load).
    expect(page).to have_current_path(%r{\A/job_orders/\d+/task/\d+/edit\z}, ignore_query: true)
    order = JobOrder.order(:id).last
    task = order.job_tasks.first
    expect(task.job_type.name).to eq("Design Services")
    # The Design Services task short-circuits the wizard: the URL stays on
    # step 1 while the reply template is the service one with its own heading.
    expect(page.current_url).to end_with("step=1")
    expect(page).to have_content("Create Job Order")
    expect(page).to have_field("comments", type: "textarea")
  end
end
