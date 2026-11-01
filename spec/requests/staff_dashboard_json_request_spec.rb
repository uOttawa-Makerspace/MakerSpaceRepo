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
    # the dashboard's user hash comes from User#serializable_hash, which leaves out
    # the password and access_token.
    expect(entry).not_to have_key("password")
    expect(entry).not_to have_key("access_token")
    expect(entry).to include("username" => visitor.username, "name" => visitor.name, "email" => visitor.email)
    expect(entry).to include("certifications", "signed_safety_sheet", "membership_status", "flagged")
    # The React app's contract: every column except the two secrets, plus the three computed keys.
    expect(entry.keys).to match_array(
      User.column_names - %w[password access_token] + %w[certifications signed_safety_sheet membership_status]
    )
  end

  it "applies the User serializer filter (later hardening of User#serializable_hash reaches it)" do
    visitor = create(:user, :regular_user)
    create(:lab_session, space: space, user: visitor, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    sign_in_as(:staff, space: space)
    allow_any_instance_of(User).to receive(:serializable_hash).and_wrap_original do |original, *args|
      original.call(*args).except("description")
    end

    get staff_dashboard_index_path, as: :json

    entry = response.parsed_body["space_users"].find { |u| u["id"] == visitor.id }
    expect(entry).not_to have_key("description")
  end

  # The exact fields MakerRepoApp reads (frontend-api-inventory.md row 9): space.id/name,
  # space_users[].{id, username, name, email, flagged, certifications[].{id,name},
  # signed_safety_sheet, membership_status}, space_list[][0] (name) and [1] (id).
  it "answers the space, the space list and the per-user certification/sheet/membership fields the React app reads" do
    other_space = create(:space)
    visitor = create(:user, :regular_user)
    create(:lab_session, space: space, user: visitor, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    cert = create(:certification, :basic_training, user: visitor)
    create(:walk_in_safety_sheet, :is_adult, user: visitor, space: space)
    create(:membership, user: visitor, end_date: 10.days.from_now)
    sign_in_as(:staff, space: space)

    get staff_dashboard_index_path, as: :json

    body = response.parsed_body
    expect(body.keys).to match_array(%w[space space_users space_list])
    expect(body["space"]).to include("id" => space.id, "name" => space.name)
    expect(body["space_list"]).to include([space.name, space.id], [other_space.name, other_space.id])
    expect(body["space_list"].all? { |name, id| name.is_a?(String) && id.is_a?(Integer) }).to be(true)
    entry = body["space_users"].sole
    expect(entry).to include(
      "id" => visitor.id, "username" => visitor.username, "name" => visitor.name,
      "email" => visitor.email, "flagged" => visitor.flagged,
      "signed_safety_sheet" => true, "membership_status" => true
    )
    expect(entry["certifications"]).to eq([{ "id" => cert.id, "name" => cert.training.name_en }])
  end

  it "reports a user without sheet, membership or certifications with explicit false/[] values" do
    visitor = create(:user, :regular_user)
    create(:lab_session, space: space, user: visitor, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    sign_in_as(:staff, space: space)

    get staff_dashboard_index_path, as: :json

    entry = response.parsed_body["space_users"].sole
    expect(entry).to include("signed_safety_sheet" => false, "membership_status" => false, "certifications" => [])
  end

  it "lists only users signed in to the staff member's space and not expired sessions" do
    here = create(:user, :regular_user)
    expired = create(:user, :regular_user)
    elsewhere = create(:user, :regular_user)
    create(:lab_session, space: space, user: here, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    create(:lab_session, space: space, user: expired, sign_in_time: 5.hours.ago, sign_out_time: 1.hour.ago)
    create(:lab_session, space: create(:space), user: elsewhere, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    sign_in_as(:staff, space: space)

    get staff_dashboard_index_path, as: :json

    expect(response.parsed_body["space_users"].map { |u| u["id"] }).to eq([here.id])
  end
end
