# frozen_string_literal: true

require "rails_helper"

# The React staff app (app.makerepo.com) reads GET /staff_dashboard.json for the
# space dashboard; it uses id, username, name, email, flagged, certifications,
# signed_safety_sheet and membership_status of each signed-in user.
RSpec.describe "Staff dashboard JSON", type: :request do
  let!(:space) { create(:space) }

  it "lists signed-in users without the password hash or access token" do
    visitor = create(:user, :regular_user, access_token: "ghp_secret_token_value")
    create(:lab_session, space: space, user: visitor, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    sign_in_as(:staff, space: space)

    get staff_dashboard_index_path, as: :json

    expect(response).to have_http_status(:ok)
    entry = response.parsed_body["space_users"].find { |u| u["id"] == visitor.id }
    # FIXED(D-I02): the dashboard built its user hash from `attributes.except("password")`,
    # bypassing User#serializable_hash and still sending access_token.
    expect(entry).not_to have_key("password")
    expect(entry).not_to have_key("access_token")
    expect(entry).to include("username" => visitor.username, "name" => visitor.name, "email" => visitor.email)
    expect(entry).to include("certifications", "signed_safety_sheet", "membership_status", "flagged")
  end
end
