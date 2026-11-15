# frozen_string_literal: true

require "rails_helper"

# The tap-in popup of the staff dashboard, after the staff member has left the
# dashboard and come back to it with Turbo in the same document: leaving ends
# the dashboard's live subscription, and each tap then shows the popup once.
RSpec.describe "Staff dashboard tap-in popup after coming back to the dashboard", type: :system do
  let(:space) { create(:space) }
  let(:staff) { create(:user, :staff, space: space) }
  let(:first_member) { create(:user, :regular_user, username: "firsttapper") }
  let(:second_member) { create(:user, :regular_user, username: "secondtapper") }

  # Live dashboard subscriptions the server holds for this staff member's
  # connections (connections left open by earlier examples belong to other users).
  def dashboard_subscriptions
    ActionCable.server.connections.select { |connection| connection.current_user&.id == staff.id }.sum do |connection|
      connection.subscriptions.identifiers.count { |id| JSON.parse(id)["channel"] == "StaffDashboardChannel" }
    end
  end

  # Records every username the popup is filled with, in order.
  def record_popup_usernames
    page.execute_script(<<~JS)
      window.popupUsernames = [];
      new MutationObserver((records) => {
        records.forEach((record) => {
          record.addedNodes.forEach((node) => window.popupUsernames.push(node.textContent));
        });
      }).observe(document.getElementById("sign-in-username"), { childList: true });
    JS
  end

  it "fills the popup once for one tap" do
    log_in_as(staff, to: staff_dashboard_index_path)
    wait_for_app_js
    page.execute_script("window.sameDocument = true")
    wait_until("dashboard not subscribed") { dashboard_subscriptions == 1 }

    page.execute_script("Turbo.visit(arguments[0])", staff_training_sessions_path)
    expect(page).to have_current_path(staff_training_sessions_path)
    wait_for_app_js
    wait_until("leaving the dashboard kept its subscription") { dashboard_subscriptions.zero? }

    page.execute_script("Turbo.visit(arguments[0])", staff_dashboard_index_path)
    expect(page).to have_current_path(staff_dashboard_index_path)
    wait_for_app_js
    # Still the first document: a full page load would start the scripts afresh.
    expect(page.evaluate_script("window.sameDocument")).to be(true)
    wait_until("dashboard not subscribed again") { dashboard_subscriptions == 1 }

    record_popup_usernames
    StaffDashboardChannel.send_tap_in(first_member, space.id)
    StaffDashboardChannel.send_tap_in(second_member, space.id)
    # Messages arrive in order, so once the second tap shows, the first is done.
    expect(page).to have_css("#signinModal #sign-in-username", exact_text: "secondtapper")
    usernames = page.evaluate_script("window.popupUsernames")
    expect(usernames.count("firsttapper")).to eq(1)
  end
end
