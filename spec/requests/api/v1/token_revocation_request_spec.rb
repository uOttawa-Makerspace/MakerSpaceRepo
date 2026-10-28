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
    expect(ApiRefreshToken.where(user_id: user.id).where(revoked_at: nil)).to be_empty
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

  describe "User#bump_token_version!" do
    it "increments in SQL (a stale instance cannot lower or repeat a version), revokes tokens, closes cables" do
      stale = User.find(user.id)
      User.where(id: user.id).update_all("token_version = token_version + 5")
      expect(stale).to receive(:disconnect_cable!)
      stale.bump_token_version!
      expect(User.find(user.id).token_version).to eq(6)
      expect(stale.token_version).to eq(6)
      expect(stale).not_to be_changed
      expect(ApiRefreshToken.where(user_id: user.id, revoked_at: nil)).to be_empty
    end

    it "rolls the version bump back when revoking the refresh tokens fails" do
      token = ApiRefreshToken.issue!(user)
      allow(ApiRefreshToken).to receive(:revoke_all_for!).and_raise(ActiveRecord::StatementInvalid, "boom")
      u = User.find(user.id)
      u.deleted = true
      expect { u.bump_token_version!(:deleted) }.to raise_error(ActiveRecord::StatementInvalid)
      row = User.unscoped.find(user.id)
      expect(row.token_version).to eq(user.token_version)
      expect(row.deleted).to be(false)
      expect(token.reload.revoked_at).to be_nil
    end

    it "is the path used by store_new_password!, admin_lock! and soft_delete!" do
      [->(u) { u.store_new_password!("Brand-new-pw-123!") }, :admin_lock!, :soft_delete!].each do |action|
        u = create(:user)
        expect(u).to receive(:bump_token_version!).and_call_original
        action.respond_to?(:call) ? action.call(u) : u.public_send(action)
      end
    end
  end
end
