# frozen_string_literal: true

require "rails_helper"

# The tap-in popup of the staff dashboard, after the staff member has visited
# the dashboard again with Turbo in the same document: the dashboard keeps
# exactly one live subscription, so the first tap after the visit shows the
# popup, and each tap shows it once.
RSpec.describe "Staff dashboard tap-in popup after visiting the dashboard again", type: :system do
  let(:space) { create(:space) }
  let(:staff) { create(:user, :staff, space: space) }
  let(:first_member) { create(:user, :regular_user, username: "firsttapper") }
  let(:second_member) { create(:user, :regular_user, username: "secondtapper") }
  let(:confirmations) { [] }

  # Counts the server's subscription confirmations for this space's dashboard channel.
  around do |example|
    callback = lambda do |*, payload|
      next unless payload[:channel_class] == "StaffDashboardChannel"

      confirmations << payload[:identifier] if JSON.parse(payload[:identifier])["space_id"] == space.id.to_s
    end
    ActiveSupport::Notifications.subscribed(callback, "transmit_subscription_confirmation.action_cable") { example.run }
  end

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

  # Visits the path with Turbo and waits until the page scripts' turbo:load
  # handlers have run (this listener is added after theirs, so it runs last).
  def turbo_visit(path)
    page.execute_script(<<~JS, path)
      document.documentElement.dataset.visited = "";
      document.addEventListener("turbo:load", () => {
        document.documentElement.dataset.visited = "done";
      }, { once: true });
      Turbo.visit(arguments[0]);
    JS
    expect(page).to have_css("html[data-visited='done']", visible: :all)
    # Still the first document: a full page load would start the scripts afresh.
    expect(page.evaluate_script("window.sameDocument")).to be(true)
  end

  def open_dashboard
    log_in_as(staff, to: staff_dashboard_index_path)
    wait_for_app_js
    page.execute_script("window.sameDocument = true")
    wait_until("dashboard subscription not confirmed") { confirmations.size == 1 }
  end

  # Two taps: the first one shows the popup, and once the second shows, the
  # first has been handled by every subscription (messages arrive in order).
  def expect_each_tap_shown_once
    record_popup_usernames
    StaffDashboardChannel.send_tap_in(first_member, space.id)
    expect(page).to have_css("#signinModal #sign-in-username", exact_text: "firsttapper")
    StaffDashboardChannel.send_tap_in(second_member, space.id)
    expect(page).to have_css("#signinModal #sign-in-username", exact_text: "secondtapper")
    expect(page.evaluate_script("window.popupUsernames").count("firsttapper")).to eq(1)
  end

  it "shows each tap once after leaving the dashboard and coming back" do
    open_dashboard

    turbo_visit(staff_training_sessions_path)
    wait_until("leaving the dashboard kept its subscription") { dashboard_subscriptions.zero? }

    turbo_visit(staff_dashboard_index_path)
    wait_until("dashboard subscription not confirmed again") { confirmations.size == 2 }

    expect_each_tap_shown_once
  end

  it "keeps its one subscription when the dashboard is visited again from itself" do
    open_dashboard

    turbo_visit(staff_dashboard_index_path(again: 1))
    expect(dashboard_subscriptions).to eq(1)
    expect(confirmations.size).to eq(1)

    expect_each_tap_shown_once
  end
end
