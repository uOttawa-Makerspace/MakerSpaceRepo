# frozen_string_literal: true

require "rails_helper"

# First system (browser) test — pins the login journey and the authenticated
# shell (Bootstrap navbar structure, user chip, footer) so refactors must
# keep rendering the same look and feel.

RSpec.describe "Login", type: :system do
  it "logs in a confirmed user and shows the authenticated homepage" do
    user = create(:user, :regular_user)

    visit login_path

    # Login page shares the global chrome (header/footer)
    expect(page).to have_css("nav.navbar.navbar-expand-xl")
    expect(page).to have_css("a.navbar-brand", text: "MakerRepo")
    expect(page).to have_css("input#username_email")
    expect(page).to have_css("input#password")

    fill_in "username_email", with: user.username
    fill_in "password", with: "asa32A353#"
    find("input[type=submit]").click

    expect(page).to have_current_path(root_path)

    # Authenticated shell: navbar still present; user dropdown chip shows
    # the username; footer rendered
    expect(page).to have_css("nav.navbar.navbar-expand-xl.shadow-lg")
    expect(page).to have_text(user.username)
    expect(page).to have_css("footer")
  end
end
