# frozen_string_literal: true

require "rails_helper"

# The sort arrows in the admin announcements table headers (src/sorting.js
# sortTable). The direction starts ascending on each page load and flips on
# every click. Real login, real page JS.
RSpec.describe "Table sort arrows", type: :system do
  let(:admin) { create(:user, :admin) }

  before do
    create(:announcement, :volunteer, description: "Bravo note", created_at: Time.zone.local(2026, 3, 5, 10))
    create(:announcement, :volunteer, description: "charlie note", created_at: Time.zone.local(2025, 12, 1, 9))
    create(:announcement, :volunteer, description: "Alpha note", created_at: Time.zone.local(2026, 1, 20, 14))
    log_in_as(admin, to: admin_announcements_path)
  end

  def descriptions
    all("table.sessions-table tbody tr td:nth-child(2)").map { |cell| cell.text.strip }
  end

  def sort_by(header)
    find("table.sessions-table th", text: header).find("span").click
  end

  it "sorts a text column ascending, ignoring case, then descending on the next click" do
    expect(descriptions).to eq(["charlie note", "Alpha note", "Bravo note"])

    sort_by("Description")
    expect(page).to have_css("table.sessions-table tbody tr:first-child td:nth-child(2)", text: "Alpha note")
    expect(descriptions).to eq(["Alpha note", "Bravo note", "charlie note"])

    sort_by("Description")
    expect(page).to have_css("table.sessions-table tbody tr:first-child td:nth-child(2)", text: "charlie note")
    expect(descriptions).to eq(["charlie note", "Bravo note", "Alpha note"])
  end

  it "sorts the date column by date, in the direction the last click left for any column" do
    sort_by("Description")
    expect(page).to have_css("table.sessions-table tbody tr:first-child td:nth-child(2)", text: "Alpha note")

    sort_by("Date Submitted")
    expect(page).to have_css("table.sessions-table tbody tr:first-child td:nth-child(2)", text: "Bravo note")
    expect(descriptions).to eq(["Bravo note", "Alpha note", "charlie note"])

    sort_by("Date Submitted")
    expect(page).to have_css("table.sessions-table tbody tr:first-child td:nth-child(2)", text: "charlie note")
    expect(descriptions).to eq(["charlie note", "Alpha note", "Bravo note"])
  end
end
