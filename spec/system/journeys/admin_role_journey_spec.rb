# frozen_string_literal: true

require "rails_helper"

# End-to-end admin journey: an admin promotes a regular user to staff from the
# user's profile (Roles tab) and the user's new access becomes visible.
RSpec.describe "Journey: admin changes a role", type: :system do
  let!(:admin) { create(:user, :admin) }
  let!(:space) { create(:space, name: "Role Space") }
  let!(:member) { create(:user, :regular_user, name: "Morgan Member") }

  before do
    allow_any_instance_of(Octokit::Client).to receive(:login).and_raise(Octokit::Unauthorized)
  end

  def open_roles_tab
    visit user_path(member.username)
    find("#admin-tab").click
    expect(page).to have_css("#admin-roles", visible: true)
  end

  it "promote regular user -> staff area becomes available -> demote again -> access is gone" do
    as_actor(:member) do
      log_in_as(member)
      expect(page).to have_no_link("Staff Area")
      visit staff_dashboard_index_path
      expect(page).to have_no_text(/search for users to sign them in or out/i)
    end

    as_actor(:admin) do
      log_in_as(admin)
      open_roles_tab
      choose "role_staff"
      click_button "Update"
      expect(member.reload.role).to eq("staff")
      open_roles_tab
      expect(page).to have_checked_field("role_staff")
    end

    as_actor(:member) do
      visit root_path
      expect(page).to have_link("Staff Area", visible: :all)
    end

    as_actor(:member) do
      visit staff_dashboard_index_path
      expect(page).to have_text(/search for users to sign them in or out/i)
    end

    as_actor(:admin) do
      open_roles_tab
      choose "role_regular_user"
      click_button "Update"
      expect(member.reload.role).to eq("regular_user")
    end

    as_actor(:member) do
      visit staff_dashboard_index_path
      expect(page).to have_no_text(/search for users to sign them in or out/i)
    end
  end
end
