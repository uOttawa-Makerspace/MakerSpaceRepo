# frozen_string_literal: true

require "rails_helper"

# INF-04: the 72-hour idle window is part of "is this cookie session valid?"
# (SessionAuthenticator.valid_for?), so it is enforced wherever the session user
# is resolved (ApplicationHelper#session_user, the cable connection, direct
# uploads). No controller can skip it. session_user also extends the window of a
# session it found valid (at most every few minutes), so any activity counts and
# an expired session is never revived.
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

  # Review follow-up: the window is extended where the session user is resolved
  # (ApplicationHelper#session_user), so activity on controllers outside
  # SessionsController keeps the session alive too.
  describe "activity outside SessionsController extends the window" do
    let!(:user) { create(:user, :staff) }
    let(:space) { create(:space) }

    it "a staff kiosk in use for more than 72 hours stays signed in" do
      start = Time.current
      log_in!
      [60, 120, 180].each do |hours|
        travel_to(start + hours.hours)
        get kiosk_path(space)
        expect(response).to have_http_status(:ok)
      end
      expect(signed_in_page_reachable?).to be(true)
    end

    it "SAML logins keep the session alive" do
      start = Time.current
      log_in!
      [60, 120].each do |hours|
        travel_to(start + hours.hours)
        get "/saml/auth", params: { SAMLRequest: authn_request }
        expect(response.body).to include('value="current_user"')
      end
      travel_to(start + 180.hours)
      post "/saml/auth", params: { SAMLRequest: authn_request, submit: "current_user" }
      expect(saml_response_present?).to be(true)
    end

    it "the window is rewritten at most every few minutes, not on every request" do
      log_in!
      get settings_profile_path
      stamp = session[:expires_at]
      travel 1.minute do
        get settings_profile_path
        expect(session[:expires_at]).to eq(stamp)
      end
      travel 10.minutes do
        get settings_profile_path
        expect(Time.zone.parse(session[:expires_at].to_s)).to be > Time.zone.parse(stamp.to_s)
      end
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
