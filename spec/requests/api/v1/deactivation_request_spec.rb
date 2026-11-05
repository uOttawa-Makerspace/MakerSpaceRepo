# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/v1 refresh tokens and deactivation", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "CONTENT_TYPE" => "application/json" } }

  def refresh(token)
    post "/api/v1/session/refresh", params: { refresh_token: token }.to_json, headers: headers
  end

  it "deactivating revokes the user's refresh tokens, so reactivating cannot revive them" do
    token = ApiRefreshToken.issue!(user)
    other = ApiRefreshToken.issue!(create(:user))

    user.deactivate!
    expect(ApiRefreshToken.where(user_id: user.id).where(revoked_at: nil)).to be_empty

    user.reactivate!
    refresh(token.raw_token)
    expect(response).to have_http_status(:unauthorized)
    expect(other.reload.revoked_at).to be_nil
  end

  it "does not revoke on other updates or on reactivation" do
    token = ApiRefreshToken.issue!(user)
    user.update!(name: "Someone Else")
    expect(token.reload.revoked_at).to be_nil
  end
end
