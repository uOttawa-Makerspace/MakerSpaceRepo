# frozen_string_literal: true

require "rails_helper"

# A token_version bump must end /api/v1 access: the access JWT through `ver`, the
# refresh tokens by explicit revocation (and their own token_version check).
RSpec.describe "/api/v1 token revocation on token_version bumps", type: :request do
  let(:password) { "asa32A353#" }
  let(:user) { create(:user) }
  let(:json_headers) { { "CONTENT_TYPE" => "application/json" } }
  let!(:pair) do
    post "/api/v1/session", params: { login: user.username, password: password }.to_json, headers: json_headers
    response.parsed_body
  end

  def refresh(token)
    post "/api/v1/session/refresh", params: { refresh_token: token }.to_json, headers: json_headers
  end

  def me(access) = get("/api/v1/session", headers: { "Authorization" => "Bearer #{access}" })

  def expect_everything_dead
    me(pair["access_token"])
    expect(response).to have_http_status(:unauthorized)
    refresh(pair["refresh_token"])
    expect(response).to have_http_status(:unauthorized)
    expect(ApiRefreshToken.where(user_id: user.id).live).to be_empty
  end

  it "is alive before any bump" do
    me(pair["access_token"])
    expect(response).to have_http_status(:ok)
  end

  it "store_new_password! (password change and reset)" do
    user.store_new_password!("Brand-new-pw-123!")
    expect_everything_dead
  end

  it "admin_lock!" do
    user.admin_lock!
    expect_everything_dead
  end

  it "admin_unlock! does not revive them" do
    user.admin_lock!
    user.admin_unlock!
    expect_everything_dead
  end

  it "soft_delete!" do
    user.soft_delete!
    expect_everything_dead
  end

  it "restore! does not revive them" do
    user.soft_delete!
    user.restore!
    expect_everything_dead
  end

  it "revokes every device of the user, not another user's" do
    other = create(:user)
    other_token = ApiRefreshToken.issue!(other)
    post "/api/v1/session", params: { login: user.username, password: password }.to_json, headers: json_headers
    second_device = response.parsed_body["refresh_token"]

    user.store_new_password!("Brand-new-pw-123!")
    refresh(second_device)
    expect(response).to have_http_status(:unauthorized)
    refresh(other_token.raw_token)
    expect(response).to have_http_status(:ok)
  end

  it "makes the refresh token unusable by token_version alone, even if the revoke were skipped" do
    user.update_columns(token_version: user.token_version + 1)
    refresh(pair["refresh_token"])
    expect(response).to have_http_status(:unauthorized)
  end
end
