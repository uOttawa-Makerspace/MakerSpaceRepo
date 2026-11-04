# frozen_string_literal: true

require "rails_helper"

# The staff "assign a locker" form (locker_rentals/assign_locker): the page script
# builds the staff header's tooltips and wires the "Indefinite" box to the end
# date. Real login, real page JS.
RSpec.describe "Assign locker form", type: :system do
  let(:staff) { create(:user, :staff) }

  before do
    log_in_as(staff)
    visit assign_locker_locker_rentals_path
  end

  it "disables and clears the end date while Indefinite is ticked" do
    expect(page).to have_field("assign_owned_until", disabled: false)

    check "Indefinite (No expiry)"
    expect(page).to have_field("assign_owned_until", disabled: true)

    uncheck "Indefinite (No expiry)"
    expect(page).to have_field("assign_owned_until", disabled: false)
  end
end
