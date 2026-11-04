# frozen_string_literal: true

require "rails_helper"

# The "Find by" box above the admin announcements table (src/sorting.js
# findSession): typing hides the rows that do not contain the text. Real login,
# real page JS.
RSpec.describe "Table search box", type: :system do
  let(:admin) { create(:user, :admin) }
  let!(:first_note) { create(:announcement, :volunteer, description: "Alpha workshop reminder") }
  let!(:second_note) { create(:announcement, :volunteer, description: "Bravo printer downtime") }

  before do
    log_in_as(admin)
    visit admin_announcements_path
  end

  it "keeps only the rows containing the typed text and shows all rows again when cleared" do
    expect(page).to have_css("table.sessions-table tbody tr", count: 2)

    fill_in "query", with: "bravo"
    expect(page).to have_css("table.sessions-table tbody tr", text: "Bravo printer downtime", count: 1)
    expect(page).to have_no_css("table.sessions-table tbody tr", text: "Alpha workshop reminder")

    fill_in "query", with: ""
    expect(page).to have_css("table.sessions-table tbody tr", text: "Alpha workshop reminder")
    expect(page).to have_css("table.sessions-table tbody tr", text: "Bravo printer downtime")
  end
end
