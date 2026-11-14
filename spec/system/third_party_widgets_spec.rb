# frozen_string_literal: true

require "rails_helper"

# The system browser resolves no external host, so Turnstile and the UserWay
# widget are blocked here. The pages must still work.
RSpec.describe "Blocked third-party widgets", type: :system do
  let(:password) { "Str0ng!Passw0rd#41" }

  it "explains the missing security check on the sign-up form and still accepts the form" do
    visit new_user_path
    expect(page).to have_css("h1", text: "Create an account")
    expect(page).to have_css(".cf-turnstile [role=alert]", text: "security check could not be loaded")
    expect(page).to have_css("[data-controller=userway][data-state=unavailable]", visible: :all)

    fill_in "user_name", with: "Blocked Widgets"
    fill_in "user_email", with: "blocked.widgets@example.com"
    fill_in "user_username", with: "blockedwidgets"
    fill_in "user_password", with: password
    fill_in "user_password_confirmation", with: password
    select "Female", from: "user_gender"
    choose "user_identity_community_member"
    check "user_read_and_accepted_waiver_form"
    find("form.form input[type=submit]").click

    expect_flash("Account has been created")
    expect(User.find_by(username: "blockedwidgets")).to be_present
  end

  it "keeps a page without a captcha working when the accessibility widget is blocked" do
    visit login_path
    expect(page).to have_css("[data-controller=userway][data-state=unavailable]", visible: :all)
    expect(page).to have_css("input[type=submit]")
  end
end

RSpec.describe "Accessibility widget across Turbo visits", type: :system do
  it "keeps one widget after several Turbo visits" do
    visit login_path
    # Stand-in for what the vendor script adds to the body.
    page.execute_script(<<~JS)
      var w = document.createElement("div");
      w.className = "userway_buttons_wrapper";
      w.dataset.original = "yes";
      window.turboKept = true;
      window.liveWidget = w;
      document.body.appendChild(w);
    JS

    page.execute_script("Turbo.visit('#{forgot_password_path}')")
    expect(page).to have_current_path(forgot_password_path)
    expect(page).to have_css("h1", exact_text: I18n.t("static_pages.forgot_password.title"))
    page.execute_script("Turbo.visit('#{login_path}')")
    expect(page).to have_current_path(login_path)
    expect(page).to have_css("h1", exact_text: I18n.t("sessions.login.sign_in"))
    expect(page.evaluate_script("window.turboKept")).to be(true)
    expect(page).to have_css(".userway_buttons_wrapper[data-original=yes]", count: 1, visible: :all)

    page.go_back
    expect(page).to have_current_path(forgot_password_path)
    expect(page).to have_css("h1", exact_text: I18n.t("static_pages.forgot_password.title"))
    expect(page).to have_css(".userway_buttons_wrapper", count: 1, visible: :all)
    expect(page.evaluate_script("document.querySelector('.userway_buttons_wrapper') === window.liveWidget")).to be(true)

    expect(page).to have_css(".userway_buttons_wrapper[data-original=yes]", count: 1, visible: :all)
    expect(page).to have_css("[data-controller=userway]", count: 1, visible: :all)
  end
end

RSpec.describe "Accessibility widget for staff and admins", type: :system do
  # Stand-in for the running vendor script and what it adds to the body.
  def start_stand_in_widget
    page.execute_script(<<~JS)
      var w = document.createElement("div");
      w.className = "userway_buttons_wrapper";
      document.body.appendChild(w);
      window.standInWidgetRunning = true;
    JS
  end

  # Turbo changes the address before it renders, so wait for a heading only the new page has.
  def turbo_visit(path, heading:)
    page.execute_script("Turbo.visit(arguments[0])", path)
    expect(page).to have_current_path(path)
    expect(page).to have_css("h1, h2", exact_text: heading)
  end

  it "keeps one document on a Turbo visit from a public page to an admin page" do
    log_in_as(create(:user, :admin))
    expect(page).to have_no_css("[data-controller=userway]", visible: :all)
    page.execute_script("window.sameDocument = true")

    turbo_visit(admin_announcements_path, heading: "Announcements")
    expect(page.evaluate_script("window.sameDocument")).to be(true)
    expect(page).to have_no_css("[data-controller=userway]", visible: :all)
  end

  it "starts a fresh document when a page opened before signing in makes a Turbo visit" do
    admin = create(:user, :admin)
    visit root_path
    expect(page).to have_css("[data-controller=userway]", visible: :all)
    start_stand_in_widget
    # Signing in from another tab: the cookie changes, this page does not.
    page.driver.browser.manage.add_cookie(name: BrowserAuthHelper::SESSION_COOKIE,
                                          value: login_cookie_for(admin, "asa32A353#"), path: "/")

    turbo_visit(admin_announcements_path, heading: "Announcements")
    expect(page).to have_no_css(".userway_buttons_wrapper", visible: :all)
    expect(page.evaluate_script("window.standInWidgetRunning")).to be_nil
  end

  it "signs staff in through the form onto a page without the widget" do
    log_in_through_form(create(:user, :staff))

    expect(page).to have_no_css("[data-controller=userway]", visible: :all)
  end
end
