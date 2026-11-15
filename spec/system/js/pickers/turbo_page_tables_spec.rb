# frozen_string_literal: true

require "rails_helper"

# Tables that a page's own script builds with DataTables (the trainings,
# locker inventory, job order and proficient project request lists): on a page
# gone back to with Turbo, and on a page reached by a Turbo visit, the table is
# built once, holds all its rows and keeps working, as on a first visit.
RSpec.describe "Page tables on Turbo visits and on going back", type: :system, skip_bullet: true do
  let(:admin) { create(:user, :admin) }

  def expect_one_built_table(id)
    expect(page).to have_css(".dt-container ##{id}", count: 1, visible: :all)
    expect(page).to have_no_css(".dt-container .dt-container", visible: :all)
    expect(page).to have_no_css("##{id} .dt-container", visible: :all)
  end

  def turbo_visit_from_admin_users(path)
    log_in_as(admin, to: admin_users_path)
    wait_for_app_js
    page.execute_script("Turbo.visit(#{path.to_json})")
    expect(page).to have_current_path(path)
  end

  def expect_page_of(id, first:, last:, total:)
    expect(page).to have_css(".dt-info", text: "Showing #{first} to #{last} of #{total} entries")
    expect(page).to have_css("##{id} tbody tr", count: last - first + 1)
  end

  def expect_second_page_of(id, total:)
    expect_page_of(id, first: 1, last: 10, total: total)
    find(".dt-paging button", text: "2").click
    expect_page_of(id, first: 11, last: total, total: total)
  end

  describe "the trainings list" do
    before { 12.times { create(:training) } }

    it "pages through every training on the page gone back to" do
      log_in_as(admin, to: admin_trainings_path)
      expect(page).to have_css(".dt-container #trainings-table", visible: :all)
      leave_and_restore(admin_trainings_path)
      expect_one_built_table("trainings-table")
      expect_second_page_of("trainings-table", total: 12)
    end

    it "is built on the page reached by a Turbo visit from another admin page" do
      turbo_visit_from_admin_users(admin_trainings_path)
      expect_one_built_table("trainings-table")
      expect_second_page_of("trainings-table", total: 12)
    end
  end

  describe "the locker inventory" do
    include_context "with lockers on"

    before do
      create(:locker, specifier: "101", locker_size: size_small, audience: "general")
      create(:locker, specifier: "102", locker_size: size_large, audience: "general")
    end

    def expect_working_search
      find("#locker_inventory_table").ancestor(".dt-container").find(".dt-search input").fill_in(with: "102")
      expect(page).to have_css("#locker_inventory_table tbody tr", count: 1)
      expect(page).to have_css("#locker_inventory_table tbody tr[data-locker-specifier='102']")
    end

    it "keeps one table that searches on the page gone back to" do
      log_in_as(admin, to: lockers_path)
      expect(page).to have_css(".dt-container #locker_inventory_table", visible: :all)
      leave_and_restore(lockers_path)
      expect_one_built_table("locker_inventory_table")
      expect(page).to have_css("#locker_inventory_table tbody tr", count: 2)
      expect_working_search
    end

    it "is built on the page reached by a Turbo visit from another admin page" do
      turbo_visit_from_admin_users(lockers_path)
      expect_one_built_table("locker_inventory_table")
      expect_working_search
    end
  end

  describe "the admin job order list" do
    before do
      owner = create(:user, :regular_user)
      2.times { make_job_order!(owner: owner, status_key: :staff_approval) }
    end

    it "keeps one table on the page gone back to" do
      log_in_as(admin, to: admin_job_orders_path)
      expect(page).to have_css(".dt-container .job-order-table", visible: :all)
      leave_and_restore(admin_job_orders_path)
      expect(page).to have_css(".dt-container .job-order-table", count: 1, visible: :all)
      expect(page).to have_no_css(".dt-container .dt-container", visible: :all)
      expect(page).to have_css(".dt-info", text: "Showing 1 to 2 of 2 entries")
    end
  end

  describe "the proficient project requests" do
    before do
      member = create(:user, :regular_user)
      12.times do
        create(:order_item, status: "Waiting for approval", user_comments: "Finished it",
                            order: create(:order, :completed, user: member))
      end
    end

    it "pages through every request on the page gone back to" do
      log_in_as(admin, to: requests_proficient_projects_path)
      expect(page).to have_css(".dt-container #prof-proj-requests", visible: :all)
      leave_and_restore(requests_proficient_projects_path)
      expect_one_built_table("prof-proj-requests")
      expect_second_page_of("prof-proj-requests", total: 12)
    end

    it "is built on the page reached by a Turbo visit from the proficient projects list" do
      log_in_as(admin, to: proficient_projects_path)
      wait_for_app_js
      page.execute_script("Turbo.visit(#{requests_proficient_projects_path.to_json})")
      expect(page).to have_current_path(requests_proficient_projects_path)
      expect_one_built_table("prof-proj-requests")
      expect_second_page_of("prof-proj-requests", total: 12)
    end
  end
end
