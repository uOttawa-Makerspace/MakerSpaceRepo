# frozen_string_literal: true

require "rails_helper"

# Tables that DataTables sorts, searches and pages (data-datatable), on a page
# gone back to with Turbo: each table is built once, holds all its rows and
# keeps working, as on a first visit.
RSpec.describe "Sortable tables on a page gone back to with Turbo", type: :system, skip_bullet: true do
  def expect_one_table_wrapper
    expect(page).to have_css("table[data-datatable]", minimum: 1, visible: :all)
    expect(page).to have_no_css(".dt-container .dt-container", visible: :all)
    expect(page).to have_no_css(".dt-container table[data-datatable] .dt-container", visible: :all)
    count = page.evaluate_script("document.querySelectorAll('table[data-datatable]').length")
    expect(page).to have_css(".dt-container", count: count, visible: :all)
  end

  describe "the admin key list" do
    let(:admin) { create(:user, :admin) }
    let(:space) { create(:space) }

    before do
      15.times { |i| create(:key, :regular_key_type, :unknown_status, number: 100 + i, space: space) }
      log_in_as(admin, to: admin_keys_path)
      expect(page).to have_css(".dt-container", minimum: 1, visible: :all)
      leave_and_restore(admin_keys_path)
      find("button[data-bs-target='#collapseTwo']").click
      find("button[data-bs-target='#collapse-all-all']").click
    end

    it "keeps every key in one table that pages, sorts and searches" do
      expect_one_table_wrapper
      within("#collapse-all-all") do
        expect(page).to have_css(".dt-info", text: "Showing 1 to 10 of 15 entries")
        expect(page).to have_css("tbody tr", count: 10)
        click_button "2"
        expect(page).to have_css(".dt-info", text: "Showing 11 to 15 of 15 entries")
        expect(page).to have_css("tbody tr", count: 5)
        find("th", text: "Key Number").click
        find("th", text: "Key Number").click
        expect(page).to have_css("tbody tr:first-child td:first-child", exact_text: "114")
        find(".dt-search input").fill_in(with: "107")
        expect(page).to have_css("tbody tr", count: 1)
        expect(page).to have_css("tbody tr td:first-child", exact_text: "107")
      end
    end
  end

  describe "the staff dashboard" do
    let(:space) { create(:space) }
    let(:staff) { create(:user, :staff, space: space) }

    def sign_in(name)
      create(:lab_session, space: space, user: create(:user, :regular_user, name: name),
                           sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    end

    def signed_in_names
      all("#signed-in-table tbody tr td:first-child a").map(&:text)
    end

    before do
      sign_in("Zoe Zephyr")
      sign_in("Adam Apple")
      log_in_as(staff, to: staff_dashboard_index_path)
      expect(page).to have_css("#signed-in-table tbody tr", count: 2)
      leave_and_restore(staff_dashboard_index_path)
    end

    it "keeps one signed-in table that sorts and searches" do
      expect_one_table_wrapper
      find("#signed-in-table th", text: "Name").click
      expect(page).to have_css("#signed-in-table tbody tr:first-child", text: "Adam Apple")
      find("#signed-in-table th", text: "Name").click
      expect(page).to have_css("#signed-in-table tbody tr:first-child", text: "Zoe Zephyr")
      find("#signed-in-table").ancestor(".dt-container").find(".dt-search input").fill_in(with: "Adam")
      expect(page).to have_css("#signed-in-table tbody tr", count: 1, text: "Adam Apple")
    end

    it "still shows a member who signs in after it was gone back to" do
      expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all)
      sign_in("Mia Middle")
      StaffDashboardChannel.broadcast_table_updates(space.id)
      expect(page).to have_css("#signed-in-table tbody tr", count: 3)
      expect(page).to have_css("#signed-in-table tbody tr", text: "Mia Middle")
      expect_one_table_wrapper
      find("#signed-in-table th", text: "Name").click
      expect(signed_in_names.first).to eq("Adam Apple")
    end
  end
end
