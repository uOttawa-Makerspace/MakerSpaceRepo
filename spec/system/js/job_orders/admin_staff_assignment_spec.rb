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
    # picked by hand: the shared picker helper ends with Escape, which also
    # closes the dialog
    wrapper = modal.find("select[name='staff_id'] + .ts-wrapper")
    wrapper.find(".ts-control").click
    wrapper.find(".ts-dropdown .option", text: "Row Staffer", exact_text: true).click
    expect(wrapper).to have_no_css(".ts-dropdown", visible: true)
    modal.click_button "Assign"

    expect(page).to have_content(I18n.t("job_orders.alerts.staff_assigned", name: "Row Staffer"))
    expect(older.reload.assigned_staff).to eq(staffer)
    expect(newer.reload.assigned_staff).to be_nil
  end
end
