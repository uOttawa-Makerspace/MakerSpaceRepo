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
end

module BrowserAuthHelper
  SESSION_COOKIE = "_MakerSpaceRepo_session"

  # System specs: signs the user in without typing into the login form. The
  # real login action runs in-process (same controller, same session cookie,
  # same CSRF check as the form), then the cookie it issued is handed to the
  # browser; this saves the login page load, the typing and the redirect
  # round-trips. The form itself is covered by log_in_through_form below.
  def log_in_as(user, password: "asa32A353#")
    visit "/robots.txt" # any cheap page on the app host, so the cookie can be set
    page.driver.browser.manage.add_cookie(name: SESSION_COOKIE, value: login_cookie_for(user, password), path: "/")
    visit root_path
    expect(page).to have_css("nav.navbar") # authenticated shell rendered
  end

  # System specs about the login page itself: drives the real login view.
  def log_in_through_form(user, password: "asa32A353#", path: login_path)
    visit path
    fill_in "username_email", with: user.username
    fill_in "password", with: password
    find("input[type=submit]").click
    expect(page).to have_css("nav.navbar") # authenticated shell rendered
  end

  private

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
