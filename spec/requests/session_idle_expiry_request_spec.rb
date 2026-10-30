# frozen_string_literal: true

require "rails_helper"

# INF-04: the 72-hour idle window is part of "is this cookie session valid?"
# (SessionAuthenticator.valid_for?), so it is enforced wherever the session user
# is resolved (ApplicationHelper#session_user, the cable connection, direct
# uploads). No controller can skip it, and refreshing the window
# (SessionsController#update_activity_time) only extends a session that is still
# alive.
RSpec.describe "Cookie session idle expiry", type: :request do
  include SamlAuthnRequestHelper

  let(:password) { "asa32A353#" }
  let!(:user) { create(:user, :regular_user) }

  def log_in!
    post login_authentication_path, params: { username_email: user.username, password: password }
    expect(response).to redirect_to(root_path)
  end

  def saml_response_present?
    Nokogiri::HTML(response.body).at_css("input#SAMLResponse").present?
  end

  def signed_in_page_reachable?
    get settings_profile_path
    response.successful?
  end

  it "a session used within 72 hours stays signed in" do
    log_in!
    travel 71.hours do
      expect(signed_in_page_reachable?).to be(true)
    end
  end

  it "an idle-expired session is not revived by /help (a page that used to skip the expiry check)" do
    log_in!
    travel 73.hours do
      get help_path
      expect(response).to have_http_status(:ok)
      expect(signed_in_page_reachable?).to be(false)
      expect(response).to redirect_to(login_path(back_to: settings_profile_path))
    end
  end

  it "an idle-expired session is not revived by /licenses or /getting-started either" do
    log_in!
    travel 73.hours do
      get getting_started_sua_path
      get licenses_cca_path
      expect(signed_in_page_reachable?).to be(false)
    end
  end

  it "SAML refuses an idle-expired session: no assertion, the login page is shown" do
    log_in!
    travel 73.hours do
      post "/saml/auth", params: { SAMLRequest: authn_request, submit: "current_user" }
      expect(response).to have_http_status(:ok)
      expect(saml_response_present?).to be(false)
      expect(response.body).to include('value="sign_in"')
    end
  end

  it "SAML still issues an assertion for a live session" do
    log_in!
    travel 71.hours do
      post "/saml/auth", params: { SAMLRequest: authn_request, submit: "current_user" }
      expect(saml_response_present?).to be(true)
    end
  end

  it "a fresh sign-in gets a full window even if the previous session's window had lapsed" do
    start = Time.current
    log_in!
    travel_to(start + 73.hours)
    log_in!
    travel_to(start + 73.hours + 71.hours)
    expect(signed_in_page_reachable?).to be(true)
  end
end
