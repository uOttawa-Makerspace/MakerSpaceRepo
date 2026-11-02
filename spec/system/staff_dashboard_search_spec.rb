# frozen_string_literal: true

require "rails_helper"

# The staff dashboard's user picker with its two forms (staff_dashboard/_search):
# Sign In submits a PUT with the page's CSRF token; View is a GET whose URL
# carries no token. Real login, real page JS (staff_dashboard_search.js copies the
# picked username into the submitted form).
RSpec.describe "Staff dashboard user picker", type: :system do
  let(:space) { create(:space) }
  let(:staff) { create(:user, :staff, space: space) }
  let!(:visitor) { create(:user, :regular_user, name: "Visiting Person") }

  def pick(user)
    expect(page).to have_css("#user_dashboard_select.tomselected", visible: :all)
    page.execute_script(<<~JS, user.username, user.name)
      const ts = document.getElementById("user_dashboard_select").tomselect;
      ts.addOption({ id: arguments[0], name: arguments[1] });
      ts.setValue(arguments[0]);
    JS
  end

  before do
    log_in_as(staff)
    visit staff_dashboard_index_path
  end

  it "Sign In signs the picked user in to the staff member's space" do
    pick(visitor)
    click_button "Sign In"
    expect(page).to have_current_path(staff_dashboard_index_path(space_id: space.id))
    expect(LabSession.where(user: visitor, space: space).count).to eq(1)
  end

  it "View opens the picked user's profile, with no CSRF token in any URL on the way" do
    requested = []
    callback = ->(_name, _start, _finish, _id, payload) { requested << payload[:request]&.fullpath }
    ActiveSupport::Notifications.subscribed(callback, "process_action.action_controller") do
      pick(visitor)
      click_button "View"
      expect(page).to have_current_path(user_path(visitor.username))
    end
    expect(requested.compact).to include(a_string_starting_with("/staff_dashboard/user_profile?"))
    expect(requested.compact.join(" ")).not_to include("authenticity_token")
  end
end
