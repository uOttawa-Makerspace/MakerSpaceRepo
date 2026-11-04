# frozen_string_literal: true

require "rails_helper"

# The admin's "New Training Session" form: the instructor select is enhanced
# by the page script (TomSelect). Real login, real page JS.
RSpec.describe "New training session form", type: :system do
  let(:admin) { create(:user, :admin) }
  let(:space) { create(:space) }

  before do
    log_in_as(admin)
    visit new_staff_training_session_path(space_id: space.id)
  end

  it "turns the instructor select into a searchable TomSelect" do
    expect(page).to have_css("select#user_id.tomselected", visible: :all)
  end
end
