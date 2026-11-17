# frozen_string_literal: true

require "rails_helper"

# The admin job order list: every unassigned row has its own Assign Staff
# button, and the dialog it opens assigns staff to that row's order.
RSpec.describe "Assigning staff from the admin job order list", type: :system do
  let(:admin) { create(:user, :admin) }
  let!(:staffer) { create(:user, :staff, name: "Row Staffer") }

  it "gives every row a staff picker, and the second row's assigns that row's order" do
    seed_job_statuses!
    owner = create(:user, :regular_user)
    older = make_job_order!(owner: owner, status_key: :staff_approval)
    newer = make_job_order!(owner: owner, status_key: :staff_approval)
    older.update!(created_at: 2.days.ago)
    newer.update!(created_at: 1.day.ago)

    log_in_as(admin, to: admin_job_orders_path)
    expect(page).to have_css("select[name='staff_id'].tomselected", count: 2, visible: :all)
    # newest first: the older order is the second row
    expect(page).to have_css("tbody tr:nth-child(2)#job-order-row-#{older.id}")

    within("#job-order-row-#{older.id}") { click_button "Assign Staff" }
    modal = find(".modal.show")
    wait_for_modal_ready("##{modal[:id]}")
    within(modal) { tom_select "Row Staffer", from: "jo-staff-select-#{older.id}" }
    expect(modal).to match_css(".show")
    modal.click_button "Assign"

    expect(page).to have_content(I18n.t("job_orders.alerts.staff_assigned", name: "Row Staffer"))
    expect(older.reload.assigned_staff).to eq(staffer)
    expect(newer.reload.assigned_staff).to be_nil
  end

  it "lists orders by submitted date, so an older order with a higher id sits below a newer one" do
    seed_job_statuses!
    owner = create(:user, :regular_user)
    newer = make_job_order!(owner: owner, status_key: :staff_approval)
    # like an imported print order: created later in the database, so a higher id, but submitted years ago
    imported = make_job_order!(owner: owner, status_key: :staff_approval)
    newer.update!(created_at: 1.day.ago)
    imported.update!(created_at: Time.zone.local(2022, 8, 15, 12))
    expect(imported.id).to be > newer.id

    log_in_as(admin, to: admin_job_orders_path)
    expect(page).to have_css("tbody tr:nth-child(1)#job-order-row-#{newer.id}")
    expect(page).to have_css("tbody tr:nth-child(2)#job-order-row-#{imported.id}")
  end
end
