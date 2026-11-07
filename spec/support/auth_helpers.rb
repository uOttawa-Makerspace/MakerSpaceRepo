# frozen_string_literal: true

# Shared helpers for request and controller specs: authentication is a custom
# session store (`session[:user_id]`), no Devise. System specs use a real login.

module AuthzTestHelper
  # Request/controller specs: shim the session directly (matches current
  # behavior pinned across the existing suite).
  def sign_in_via_session(user)
    session[:user_id] = user.id
    user
  end

  # The answer of an admin-only page: a guest is sent to the login page (with
  # the page to come back to), anyone else signed in goes to the home page.
  def expect_admin_area_bounce(guest:)
    if guest
      expect(response).to have_http_status(:found)
      expect(URI.parse(response.location).path).to eq(login_path)
    else
      expect(response).to redirect_to("/")
    end
  end
end

module BrowserAuthHelper
  SESSION_COOKIE = "_MakerSpaceRepo_session"

  # System specs: signs the user in without typing into the login form. The
  # real login action runs in-process (same controller, same session cookie,
  # same CSRF check as the form), then the cookie it issued is handed to the
  # browser; this saves the login page load, the typing and the redirect
  # round-trips. The form itself is covered by log_in_through_form below.
  #
  # `to:` is the page to land on (checked for the signed-in header); local_storage
  # entries are written on the cheap page before that load, so a page script can
  # read them as it starts.
  def log_in_as(user, password: "asa32A353#", to: root_path, local_storage: {})
    visit "/robots.txt" # any cheap page on the app host, so the cookie can be set
    page.driver.browser.manage.add_cookie(name: SESSION_COOKIE, value: login_cookie_for(user, password), path: "/")
    local_storage.each { |key, value| page.execute_script("localStorage.setItem(arguments[0], arguments[1])", key.to_s, value) }
    visit to
    expect_signed_in
  end

  # System specs about the login page itself: drives the real login view.
  def log_in_through_form(user, password: "asa32A353#", path: login_path)
    visit path
    fill_in "username_email", with: user.username
    fill_in "password", with: password
    find("input[type=submit]").click
    expect_signed_in
  end

  private

  # Only a signed-in user gets the sign-out form (inside the user dropdown, so hidden).
  def expect_signed_in
    return if page.has_css?("form[action='#{perform_logout_path}']", visible: :all)

    raise "Not signed in: the page has no sign-out form (session cookie missing or rejected)"
  end

  def login_cookie_for(user, password)
    http = ActionDispatch::Integration::Session.new(Rails.application)
    http.get login_path
    token = Nokogiri::HTML(http.response.body).at_css("form[action='#{login_authentication_path}'] input[name=authenticity_token]")["value"]
    http.post login_authentication_path, params: { username_email: user.username, password:, authenticity_token: token }
    raise "sign-in failed (#{http.response.status})" unless http.response.redirect?

    Rack::Utils.escape(http.cookies[SESSION_COOKIE]) # the jar holds the decoded value; the browser stores it as sent
  end
end

RSpec.configure do |config|
  config.include AuthzTestHelper, type: :request
  config.include AuthzTestHelper, type: :controller
  config.include BrowserAuthHelper, type: :system
end
