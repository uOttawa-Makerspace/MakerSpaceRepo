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
  # System specs: drive the real login view. Keeps look-and-feel tests honest
  # (login page renders + session cookie is set by the app, not by us).
  def log_in_as(user, password: "asa32A353#", path: login_path)
    visit path
    fill_in "username_email", with: user.username
    fill_in "password", with: password
    find("input[type=submit]").click
    expect(page).to have_css("nav.navbar") # authenticated shell rendered
  end
end

RSpec.configure do |config|
  config.include AuthzTestHelper, type: :request
  config.include AuthzTestHelper, type: :controller
  config.include BrowserAuthHelper, type: :system
end
