# frozen_string_literal: true

require "rails_helper"

# Deactivating sets `active` and bumps token_version in one UPDATE, so reactivating
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
    expect(User.find(user.id).active).to be(false)
    user.reactivate!
    row = User.find(user.id)
    expect([row.active, row.token_version]).to eq([true, version + 2])

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
    expect(User.unscoped.find(user.id)).to have_attributes(active: false, deleted: true)
  end

  it "a deactivated admin no longer counts as a usable admin" do
    admin = create(:user, :admin)
    create(:user, :admin)
    expect(User.usable_admins).to include(admin)
    admin.deactivate!
    expect(User.usable_admins).not_to include(admin)
  end
end
