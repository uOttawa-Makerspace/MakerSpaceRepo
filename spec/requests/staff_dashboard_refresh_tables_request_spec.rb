# frozen_string_literal: true

require "rails_helper"

# GET /staff_dashboard/refresh_tables: a JSON blob with the signed-in/signed-out
# table rows as rendered HTML plus the "latest sign-in" details (the same keys,
# users/certification/has_membership/expiration_date/is_student/signed_sheet,
# that the staff dashboard's tap-in modal reads). The latest sign-in is the
# first of Space#signed_in_users, which is ordered by sign_out_time DESC.
#
# under CI=1 Bullet raises on this endpoint with 2+ signed-in users: the
# signed_in partial calls `user.walk_in_safety_sheets.any?` per row (N+1; Bullet asks for
# `.includes(:walk_in_safety_sheets)`). Pinned with skip_bullet, as for the other pinned N+1s.
RSpec.describe "Staff dashboard refresh_tables", type: :request, skip_bullet: true do
  include StaffDashboardSpecHelpers

  let!(:space) { create(:space) }
  let!(:other_space) { create(:space) }
  let!(:staff) { sign_in_as(:staff, space: space) }

  let(:tier) { create(:membership_tier, title_en: "Community Plus") }
  # "latest": ends last, so it is first in Space#signed_in_users
  let!(:latest) { create(:user, :regular_user, :student, name: "Latest Visitor") }
  let!(:earlier) { create(:user, :regular_user, name: "Earlier Visitor") }
  let!(:gone) { create(:user, :regular_user, name: "Gone Visitor") }
  let!(:elsewhere) { create(:user, :regular_user, name: "Elsewhere Visitor") }

  before do
    create(:lab_session, space: space, user: earlier, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    create(:lab_session, space: space, user: latest, sign_in_time: 30.minutes.ago, sign_out_time: 3.hours.from_now)
    create(:lab_session, space: space, user: gone, sign_in_time: 3.hours.ago, sign_out_time: 1.hour.ago)
    create(:lab_session, space: other_space, user: elsewhere, sign_in_time: 30.minutes.ago, sign_out_time: 3.hours.from_now)
  end

  def refresh(params = {})
    get "/staff_dashboard/refresh_tables", params: params
  end

  it "answers JSON with the signed-in users, in sign-out order, as [name, email, username] triples" do
    refresh

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(json.keys).to match_array(%w[users certification has_membership expiration_date is_student signed_sheet signed_out signed_in])
    expect(json["users"]).to eq([
      [latest.name, latest.email, latest.username],
      [earlier.name, earlier.email, earlier.username]
    ])
  end

  it "describes the latest sign-in: plain visitor has no membership, sheet or certifications" do
    refresh

    expect(json).to include(
      "certification" => [],
      "has_membership" => false,
      "expiration_date" => "",
      "is_student" => true,
      "signed_sheet" => false
    )
  end

  it "describes the latest sign-in: membership expiry, signed walk-in sheet and certifications" do
    membership = create(:membership, user: latest, membership_tier: tier, end_date: 12.days.from_now)
    create(:walk_in_safety_sheet, :is_adult, user: latest, space: space)
    cert = create(:certification, :basic_training, user: latest)
    # the data is about the FIRST signed-in user only: certs of the other visitor are not included
    create(:certification, :"3d_printing", user: earlier)

    refresh

    expect(json["has_membership"]).to be(true)
    expect(json["expiration_date"]).to eq(membership.end_date.to_date.to_s)
    expect(json["is_student"]).to be(true)
    expect(json["signed_sheet"]).to be(true)
    expect(json["certification"]).to eq([[latest.id, [{ "id" => cert.id, "user_id" => latest.id, "name_en" => cert.training.name_en }]]])
  end

  it "renders a signed_in table row per signed-in user of THIS space and none for others" do
    create(:membership, user: latest, membership_tier: tier, end_date: 12.days.from_now)

    refresh

    html = json["signed_in"]
    expect(html).to include("data-user-id=#{latest.id}", "data-user-id=#{earlier.id}")
    expect(html).to include(latest.email, earlier.email, "/#{latest.username}", "/#{earlier.username}")
    expect(html).to include("Has a Community Membership") # latest: student with an active membership
    expect(html.scan("data-user-id=").size).to eq(2)
    expect(html).not_to include(gone.email)
    expect(html).not_to include(elsewhere.email)
    # each row has the sign-out button for that username
    expect(html).to include("dropped_users%5B%5D=#{latest.username}", "dropped_users%5B%5D=#{earlier.username}")
  end

  it "renders the recently signed-out users, with a sign-in button, and not the signed-in ones" do
    refresh

    html = json["signed_out"]
    expect(html).to include('<tbody id="table-js-signed-out">')
    expect(html).to include(gone.email, "added_users%5B%5D=#{gone.username}", "about 1 hour ago at #{space.name}")
    expect(html).not_to include(latest.email)
    expect(html).not_to include(earlier.email)
    expect(html).not_to include(elsewhere.email)
  end

  it "answers 304 with no body when the token is the concatenated signed-in user ids (nothing changed)" do
    refresh(token: "#{latest.id}#{earlier.id}")

    expect(response).to have_http_status(:not_modified)
    expect(response.body).to be_empty
  end

  # the token is `signed_in_user_ids.join("")`, with no separator, so different
  # signed-in sets can produce the same token (ids [9_000_001, 7_777_777] and [90_000_017, 777_777]
  # are both "90000017777777"). The client holding the first set's token gets a 304 for the second set and
  # keeps showing stale people. A separator-joined token would not collide.
  it "answers 304 for a different signed-in set whose ids concatenate to the same token" do
    third_space = create(:space)
    staff.update!(space: third_space)
    # explicit ids far above any users_id_seq value (the sequence is not rolled back between examples)
    a = create(:user, :regular_user, id: 9_000_001)
    b = create(:user, :regular_user, id: 7_777_777)
    c = create(:user, :regular_user, id: 90_000_017)
    d = create(:user, :regular_user, id: 777_777)
    expect("#{a.id}#{b.id}").to eq("#{c.id}#{d.id}") # precondition: the two sets collide
    create(:lab_session, space: third_space, user: a, sign_in_time: 1.hour.ago, sign_out_time: 3.hours.from_now)
    create(:lab_session, space: third_space, user: b, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    refresh
    stale_token = "#{a.id}#{b.id}"
    expect(json["users"].map(&:last)).to eq([a.username, b.username])

    # the room changes completely: a and b leave, c and d arrive
    LabSession.where(user: [a, b]).update_all(sign_out_time: 1.minute.ago)
    create(:lab_session, space: third_space, user: c, sign_in_time: 30.minutes.ago, sign_out_time: 3.hours.from_now)
    create(:lab_session, space: third_space, user: d, sign_in_time: 30.minutes.ago, sign_out_time: 2.hours.from_now)

    refresh(token: stale_token)

    expect(stale_token).to eq("#{c.id}#{d.id}")
    expect(response).to have_http_status(:not_modified) # should be 200 with c and d
    expect(response.body).to be_empty
  end

  it "answers the full payload when the token is stale" do
    refresh(token: "#{earlier.id}#{latest.id}") # same ids, wrong order

    expect(response).to have_http_status(:ok)
    expect(json["users"].size).to eq(2)
  end

  it "follows the staff member's space" do
    staff.update!(space: other_space)

    refresh

    expect(json["users"]).to eq([[elsewhere.name, elsewhere.email, elsewhere.username]])
    expect(json["signed_out"]).not_to include(gone.email)
  end

  it "refuses a regular user (redirect to root) and a guest (redirect to login)" do
    delete logout_path
    get "/staff_dashboard/refresh_tables"
    expect(response).to have_http_status(:found)
    expect(response.location).to start_with("http://www.example.com/login")

    sign_in_as(:regular)
    get "/staff_dashboard/refresh_tables"
    expect(response).to redirect_to(root_path)
  end

  context "when nobody is signed in to the space" do
    before { LabSession.where(space: space).update_all(sign_out_time: 1.minute.ago) }

    it "is a 500 (NoMethodError on nil), the polled endpoint fails on an empty room" do
      # not only "no space context". `@space.signed_in_users.first.memberships`
      # is called without a nil check, so ANY staff dashboard with zero signed-in users (an empty lab,
      # the normal state overnight) gets a 500 from this endpoint instead of empty tables.
      refresh

      expect(response).to have_http_status(:internal_server_error)
      expect(exception_class).to eq("NoMethodError")
      expect(response.body[/<h1>\s*(\S+)\s+in (\S+)/, 2]).to eq("StaffDashboardController#refresh_tables")
    end
  end
end
