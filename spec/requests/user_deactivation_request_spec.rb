# frozen_string_literal: true

require "rails_helper"

# Deactivating sets `deactivated_at` and bumps token_version in one UPDATE, so reactivating
# does not revive anything issued before: cookie session, access JWT, legacy JWT,
# refresh token.
RSpec.describe "User#deactivate! / #reactivate!", type: :request do
  let(:password) { "asa32A353#" }
  let(:user) { create(:user) }
  let(:json_headers) { { "CONTENT_TYPE" => "application/json" } }

  def signed_in? = (get(check_signed_in_path) && response.parsed_body["signed_in"] == "true")

  before do
    post login_authentication_path, params: { username_email: user.username, password: password }
  end

  def api_pair
    post "/api/v1/session", params: { login: user.username, password: password }.to_json, headers: json_headers
    response.parsed_body
  end

  def expect_old_credentials_dead(pair, legacy_jwt)
    expect(signed_in?).to be(false)
    get "/api/v1/session", headers: { "Authorization" => "Bearer #{pair['access_token']}" }
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/session/refresh", params: { refresh_token: pair["refresh_token"] }.to_json, headers: json_headers
    expect(response).to have_http_status(:unauthorized)
    get check_signed_in_path, headers: { "Authorization" => "Bearer #{legacy_jwt}" }
    expect(response.parsed_body["signed_in"]).not_to eq("true")
  end

  it "deactivate then reactivate leaves the old cookie session, access JWT, legacy JWT and refresh token dead" do
    expect(signed_in?).to be(true)
    pair = api_pair
    legacy = user.token
    version = user.token_version

    user.deactivate!
    expect(User.find(user.id).deactivated_at).to be_present
    user.reactivate!
    row = User.find(user.id)
    expect([row.deactivated_at, row.token_version]).to eq([nil, version + 2])

    expect_old_credentials_dead(pair, legacy)
    expect(ApiRefreshToken.where(user_id: user.id, revoked_at: nil)).to be_empty
  end

  it "a fresh login after reactivation works" do
    user.deactivate!
    user.reactivate!
    post login_authentication_path, params: { username_email: user.username, password: password }
    expect(signed_in?).to be(true)
  end

  it "deactivate! works on a soft-deleted row and keeps the instance clean" do
    user.soft_delete!
    user.deactivate!
    expect(user).not_to be_changed
    expect(User.unscoped.find(user.id)).to have_attributes(deactivated_at: be_present, deleted: true)
  end

  it "a deactivated admin no longer counts as a usable admin" do
    admin = create(:user, :admin)
    create(:user, :admin)
    expect(User.usable_admins).to include(admin)
    admin.deactivate!
    expect(User.usable_admins).not_to include(admin)
  end

  it "deactivate! revokes the cookie session, access JWT, legacy JWT and refresh token at once" do
    expect(signed_in?).to be(true)
    pair = api_pair
    legacy = user.token

    user.deactivate!
    expect_old_credentials_dead(pair, legacy)
    expect(ApiRefreshToken.where(user_id: user.id, revoked_at: nil)).to be_empty
  end

  it "deactivate! never writes the legacy active column" do
    expect { user.deactivate! }.not_to(change { User.find(user.id).active })
    expect { user.reactivate! }.not_to(change { User.find(user.id).active })
  end

  describe "a user with legacy active = false and deactivated_at NULL" do
    before do
      User.where(id: user.id).update_all(active: false)
      expect(User.find(user.id)).to have_attributes(active: false, deactivated_at: nil)
    end

    it "signs in (cookie session) and keeps the session" do
      post login_authentication_path, params: { username_email: user.username, password: password }
      expect(signed_in?).to be(true)
    end

    it "is accepted by the access JWT, legacy JWT, refresh token and cable connection" do
      pair = api_pair
      expect(response).to have_http_status(:created).or have_http_status(:ok)
      get "/api/v1/session", headers: { "Authorization" => "Bearer #{pair['access_token']}" }
      expect(response).to have_http_status(:ok)
      post "/api/v1/session/refresh", params: { refresh_token: pair["refresh_token"] }.to_json, headers: json_headers
      expect(response).to have_http_status(:ok)
      get check_signed_in_path, headers: { "Authorization" => "Bearer #{user.token}" }
      expect(response.parsed_body["signed_in"]).to eq("true")

      fresh = User.find(user.id)
      expect(AuthEligibility.allowed?(fresh)).to be(true)
      expect(SessionAuthenticator.valid_for?({ user_id: fresh.id, token_version: fresh.token_version }, fresh)).to be(true)
    end
  end
end
