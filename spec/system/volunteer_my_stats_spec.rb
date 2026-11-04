# frozen_string_literal: true

require "rails_helper"

# The volunteer "My Stats" page: picking a certification in the quick-jump
# search brings the Skills tab to the front (volunteers.js). Real login, real
# page JS.
RSpec.describe "Volunteer my stats quick jump", type: :system, skip_bullet: true do
  let(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let!(:training) { create(:training, name_en: "Laser Cutting") }

  before do
    log_in_as(volunteer)
    visit my_stats_volunteers_path
  end

  it "switches back to the skills tab when a certification is picked from another tab" do
    expect(page).to have_css("#training-search-select.tomselected", visible: :all)
    find("#history-tab").click
    expect(page).to have_css("#history-tab.active")

    page.execute_script(
      "document.getElementById('training-search-select').tomselect.setValue(arguments[0])",
      "training-card-#{training.id}"
    )

    expect(page).to have_css("#skills-tab.active")
    expect(page).to have_css("#history-tab:not(.active)")
  end
end
