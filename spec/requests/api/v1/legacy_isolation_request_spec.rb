# frozen_string_literal: true

require "rails_helper"

# API access tokens must not open the legacy (cookie-era) Bearer paths, even when
# both are signed with the same key; legacy tokens keep working there.
RSpec.describe "API access tokens on legacy Bearer paths", type: :request do
  let(:user) { create(:user) }
  let(:api_token) { ApiAccessToken.issue(user).first }

  it "JwtAuthenticator refuses an API access token and accepts a legacy token" do
    expect(JwtAuthenticator.user_for("Bearer #{api_token}")).to be_nil
    expect(JwtAuthenticator.user_for("Bearer #{user.token}")).to eq(user)
  end

  it "does not sign the caller in at /check_signed_in" do
    get check_signed_in_path, headers: { "Authorization" => "Bearer #{api_token}" }
    expect(response.parsed_body["signed_in"]).to eq("false")
  end

  it "still signs in a legacy token at /check_signed_in" do
    get check_signed_in_path, headers: { "Authorization" => "Bearer #{user.token}" }
    expect(response.parsed_body["signed_in"]).to eq("true")
  end

  it "is refused by the shared validator used for direct uploads and ActionCable (both call JwtAuthenticator)" do
    expect(JwtAuthenticator.user_for("Bearer #{api_token}")).to be_nil
  end
end
