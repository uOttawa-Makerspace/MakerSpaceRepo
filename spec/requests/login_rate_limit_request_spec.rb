# frozen_string_literal: true

require "rails_helper"

# The password-guess budget (10 per 3 minutes per IP) shared by
# SessionsController#login_authentication (HTML + JSON) and
# SamlIdpController#auth (submit=sign_in).
#
# The test env cache is :null_store, which never counts, so the other specs
# stub `increment`. Here the limiter's store is backed by a REAL
# ActiveSupport::Cache::MemoryStore for the example (counting and expiry are the
# real store's; the limiter's key, scope, limit and window are the app's own).
# `rate_limit` binds the store object when the controller class is loaded, so the
# example forwards that object's `increment` to the MemoryStore and RSpec
# restores the original afterwards.
RSpec.describe "Login rate limit (real cache store)", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include SamlAuthnRequestHelper

  let(:password) { "asa32A353#" }
  let!(:user) { create(:user, :regular_user, password: BCrypt::Password.create(password)) }
  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    expect(SessionsController.cache_store).to equal(SamlIdpController.cache_store)
    allow(SessionsController.cache_store).to receive(:increment) do |*args, **opts|
      memory_store.increment(*args, **opts)
    end
  end

  # Unknown usernames: every failure is the plain refusal and never locks an account.
  def failed_html_login(n = 0, ip: nil, as: nil)
    post login_authentication_path,
         params: { username_email: "nobody-#{n}", password: "wrong" },
         env: ip ? { "REMOTE_ADDR" => ip } : {},
         as: as
  end

  def failed_saml_login(n = 0, ip: nil, username: "nobody-#{n}", pw: "wrong")
    post "/saml/auth",
         params: { SAMLRequest: authn_request, RelayState: "rs1", submit: "sign_in", username: username, password: pw },
         env: ip ? { "REMOTE_ADDR" => ip } : {}
  end

  def expect_refused_normally
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).not_to include("Too many requests")
  end

  def expect_rate_limited_json
    expect(response).to have_http_status(:too_many_requests)
    expect(JSON.parse(response.body)).to eq("error" => "Too many requests")
  end

  it "refuses 10 failed HTML logins normally, then answers the 11th with 429 (and not even the right password gets in)" do
    10.times do |i|
      failed_html_login(i)
      expect_refused_normally
    end
    failed_html_login(10)
    expect_rate_limited_json

    post login_authentication_path, params: { username_email: user.username, password: password }
    expect(response).to have_http_status(:too_many_requests)
    expect(session[:user_id]).to be_nil
  end

  it "limits the JSON login with the same 10-then-429 budget" do
    10.times do |i|
      failed_html_login(i, as: :json)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to start_with("Could not find user")
    end
    failed_html_login(10, as: :json)
    expect_rate_limited_json
  end

  it "shares one budget between HTML, JSON and SAML sign-in: 3 HTML + 3 JSON + 4 SAML, then every surface is refused" do
    3.times { |i| failed_html_login(i) ; expect_refused_normally }
    3.times { |i| failed_html_login(i + 3, as: :json); expect(response).to have_http_status(:unprocessable_content) }
    4.times do |i|
      failed_saml_login(i)
      expect(response).to have_http_status(:ok)
    end

    failed_saml_login(99)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include("Too many requests. Please wait a few minutes and try again.")

    failed_html_login(100)
    expect_rate_limited_json
  end

  it "counts SAML attempts against the HTML login budget: 6 SAML + 4 HTML, then the next HTML login is refused" do
    6.times { |i| failed_saml_login(i); expect(response).to have_http_status(:ok) }
    4.times { |i| failed_html_login(i); expect_refused_normally }
    failed_html_login(10)
    expect_rate_limited_json
  end

  it "counts HTML attempts against the SAML budget: 6 HTML + 4 SAML, then the next SAML sign-in is refused, valid password or not" do
    6.times { |i| failed_html_login(i); expect_refused_normally }
    4.times { |i| failed_saml_login(i); expect(response).to have_http_status(:ok) }
    failed_saml_login(0, username: user.username, pw: password)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).not_to include("SAMLResponse")
  end

  it "does not touch another IP's budget" do
    10.times { |i| failed_html_login(i) }
    failed_html_login(10)
    expect(response).to have_http_status(:too_many_requests)

    failed_html_login(11, ip: "203.0.113.50")
    expect_refused_normally
    failed_saml_login(12, ip: "203.0.113.50")
    expect(response).to have_http_status(:ok)
    post login_authentication_path, params: { username_email: user.username, password: password }, env: { "REMOTE_ADDR" => "203.0.113.50" }
    expect(response).to redirect_to(root_path)
  end

  it "keeps refusing inside the 3-minute window and allows logins again once it has passed" do
    start = Time.zone.now
    travel_to(start) do
      10.times { |i| failed_html_login(i) }
      failed_html_login(10)
      expect(response).to have_http_status(:too_many_requests)
    end

    travel_to(start + 2.minutes + 30.seconds) do
      failed_html_login(11)
      expect(response).to have_http_status(:too_many_requests)
    end

    travel_to(start + 3.minutes + 1.second) do
      failed_html_login(12)
      expect_refused_normally
      post login_authentication_path, params: { username_email: user.username, password: password }
      expect(response).to redirect_to(root_path)
    end
  end

  it "does not count GET /login" do
    12.times { get login_path }
    expect(response).to have_http_status(:ok)
    failed_html_login(0)
    expect_refused_normally
  end
end
