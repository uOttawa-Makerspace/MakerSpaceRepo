# frozen_string_literal: true

require "rails_helper"

RSpec.describe "New announcement form", type: :system do
  let(:admin) { create(:user, :admin) }

  before { log_in_as(admin, to: new_admin_announcement_path) }

  it "sets the end date with the calendar and clears it" do
    expect(page).to have_css("#end_date.flatpickr-input", visible: :all)
    page.execute_script("document.querySelector('#end_date')._flatpickr.setDate(new Date(Date.now() + 86400000 * 3), true)")
    expect(page.evaluate_script("document.querySelector('#end_date').value")).to match(/\A\d{4}-\d{2}-\d{2}\z/)

    click_button "Clear End Date"

    expect(page.evaluate_script("document.querySelector('#end_date').value")).to eq("")
  end
end
