# frozen_string_literal: true

require "rails_helper"

# End-to-end identity journey: register through the sign-up form, try to log in
# unconfirmed, follow the confirmation link from the delivered mail, log in and
# edit the profile.
RSpec.describe "Journey: identity", type: :system do
  let(:password) { "Str0ng!Passw0rd#41" }

  before do
    allow_any_instance_of(Octokit::Client).to receive(:login).and_raise(Octokit::Unauthorized)
    ActionMailer::Base.deliveries.clear
  end

  it "register -> confirmation mail link -> log in -> edit profile" do
    visit new_user_path
    expect(page).to have_css("h1", text: "Create an account")
    fill_in "user_name", with: "Jess Journey"
    fill_in "user_email", with: "jess.journey@example.com"
    fill_in "user_username", with: "jessjourney"
    fill_in "user_password", with: password
    fill_in "user_password_confirmation", with: password
    select "Female", from: "user_gender"
    choose "user_identity_community_member"
    check "user_read_and_accepted_waiver_form"
    find("form.form input[type=submit]").click

    expect(page).to have_current_path(root_path)
    expect(page).to have_text("Account has been created, please look in your emails to confirm your email address.")

    created = User.find_by!(username: "jessjourney")
    expect(created.confirmed).to be(false)
    expect(created.role).to eq("regular_user")
    mail = deliver_mail.find { |m| m.subject == "Makerepo | Please confirm your email" }
    expect(mail.to).to eq(["jess.journey@example.com"])
    confirm_path = link_path_in_mail(mail, %r{/confirm\?token=})

    # follow the link from the email
    visit confirm_path
    expect(page).to have_current_path(root_path)
    expect(page).to have_text("The email has been confirmed, you can now fully use your Makerepo Account !")
    expect(created.reload.confirmed).to be(true)
    welcome = deliver_mail.find { |m| m.to == ["jess.journey@example.com"] && m.subject != mail.subject }
    expect(welcome).to be_present

    # log in with the new account and edit the profile
    visit login_path
    fill_in "username_email", with: "jessjourney"
    fill_in "password", with: password
    find("input[type=submit]").click
    expect(page).to have_css("nav.navbar")
    expect(page).to have_text("jessjourney")

    visit settings_profile_path
    expect(page).to have_css("input#user_name[value='Jess Journey']")
    fill_in "user_name", with: "Jess Renamed"
    click_button "Save Changes"
    expect(page).to have_css("input#user_name[value='Jess Renamed']")
    expect(created.reload.name).to eq("Jess Renamed")

    visit user_path("jessjourney")
    expect(page).to have_text("jessjourney")
  end
end
