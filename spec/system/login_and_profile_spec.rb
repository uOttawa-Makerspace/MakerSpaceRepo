# frozen_string_literal: true

require "rails_helper"

# System (browser) characterization for the identity journey: log in, view the
# public profile, edit a profile field in settings, and see it persisted.
# Pins DOM structure only; the browser journey uses no external HTTP.
# Net::HTTP is NOT globally blocked here because Selenium talks to chromedriver
# over Net::HTTP on localhost.

RSpec.describe "Login and profile", type: :system do
  let(:user) { create(:user, :regular_user, name: "Pat Example") }


  it "logs in, shows the profile page and edits the name in settings" do
    log_in_as(user)
    expect(page).to have_current_path(root_path)

    visit user_path(user.username)
    expect(page).to have_css("nav.navbar")
    expect(page).to have_css("img.profile-img[alt='Avatar']")
    expect(page).to have_text(user.username)
    expect(page).to have_css(".profile-work")

    visit settings_profile_path
    expect(page).to have_css("form.needs-validation input#user_name[value='Pat Example']")
    fill_in "user_name", with: "Pat Renamed"
    click_button "Save Changes"

    expect(page).to have_text("Profile updated successfully.")
    expect(page).to have_current_path(settings_profile_path)
    expect(page).to have_css("input#user_name[value='Pat Renamed']")
    expect(user.reload.name).to eq("Pat Renamed")
  end

  it "shows an inline validation message when the name is blank" do
    log_in_as(user)
    visit settings_profile_path
    fill_in "user_name", with: ""
    click_button "Save Changes"

    # the PATCH redirects back to this same path, so the path alone proves
    # nothing: wait for the failure flash the redirect renders
    expect(page).to have_text("Could not save changes.")
    expect(page).to have_current_path(settings_profile_path)
    expect(user.reload.name).to eq("Pat Example")
  end

  # INF-02: the settings form POSTs with the current password; the emailed link
  # opens a confirmation page whose button POSTs the token.
  it "changes the email: settings form with the current password, then the emailed link's confirm page" do
    log_in_as(user)
    visit settings_admin_path
    fill_in "new_email", with: "pat.new@example.com"
    fill_in "confirm_new_email", with: "pat.new@example.com"
    fill_in "current_password", with: "asa32A353#"
    click_button "Update Email"
    expect(page).to have_text("A confirmation email has been sent to the new email")

    mail = ActionMailer::Base.deliveries.find { |m| m.to == ["pat.new@example.com"] }
    token = CGI.unescape(mail.body.to_s[/confirm_edited_email\?token=([^"'&\s<]+)/, 1])
    visit confirm_edited_email_users_path(token: token)
    expect(page).to have_text("Confirm your new email address")
    expect(user.reload.email).not_to eq("pat.new@example.com")

    click_button "Confirm email change"
    expect(page).to have_text("The email has been updated to pat.new@example.com !")
    expect(user.reload.email).to eq("pat.new@example.com")
  end

  it "redirects a guest from settings to the login form with back_to" do
    visit settings_profile_path
    expect(page).to have_current_path(/\/login\?back_to=%2Fsettings%2Fprofile/)
    expect(page).to have_css("input#username_email")
  end

  # js_errors: :allow, the 422 response to the bad login is logged by Chrome as a SEVERE resource error
  it "rejects a wrong password with the incorrect-password alert and stays on the form", js_errors: :allow do
    visit login_path
    fill_in "username_email", with: user.username
    fill_in "password", with: "wrong-password"
    find("input[type=submit]").click
    expect(page).to have_text("Incorrect password.")
    expect(page).to have_css("input#username_email")
  end

  it "logging out returns to the homepage as a guest" do
    log_in_as(user)
    visit logout_path
    expect(page).to have_current_path(root_path)
    visit settings_profile_path
    expect(page).to have_css("input#username_email")
  end
end
