# frozen_string_literal: true

require "rails_helper"

# The staff dashboard's sign in / sign out / search / change_space endpoints as the
# React app (MakerRepoApp, rows 6, 19, 20, 21 of doc/refactor/frontend-api-inventory.md)
# calls them: PUT add_users?added_users=:username, PUT remove_users?dropped_users[]=:username,
# GET search?query=, PUT change_space?space_id=. Plus the not-signed-in / unknown-user edges.
RSpec.describe "Staff dashboard sign in/out (JSON contract)", type: :request do
  include StaffDashboardSpecHelpers
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space) }
  let!(:other_space) { create(:space) }
  let!(:staff) { sign_in_as(:staff, space: space) }
  let(:visitor) { create(:user, :regular_user) }

  describe "PUT /staff_dashboard/add_users (sign_in_users)" do
    it "signs the user in to the staff member's space for 6 hours and answers {status: ok}" do
      freeze_time do
        put "/staff_dashboard/add_users", params: { added_users: visitor.username }, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
        expect(json).to eq("status" => "ok")
        row = LabSession.where(user: visitor).sole
        expect(row.space_id).to eq(space.id)
        expect(row.sign_in_time).to eq(Time.zone.now)
        expect(row.sign_out_time).to eq(Time.zone.now + 6.hours)
      end
    end

    it "accepts the legacy `username` param too" do
      put "/staff_dashboard/add_users", params: { username: visitor.username }, as: :json
      expect(json).to eq("status" => "ok")
      expect(LabSession.where(user: visitor, space: space).active.count).to eq(1)
    end

    it "an unknown username is silently ignored: {status: ok}, no session" do
      expect { put "/staff_dashboard/add_users", params: { added_users: "nobody" }, as: :json }.not_to change(LabSession, :count)
      expect(json).to eq("status" => "ok")
    end

    it "signs in several usernames at once" do
      other = create(:user, :regular_user)
      expect {
        put "/staff_dashboard/add_users", params: { added_users: [visitor.username, other.username] }, as: :json
      }.to change(LabSession, :count).by(2)
    end

    it "refuses a regular user and signs nobody in" do
      sign_in_as(:regular)
      expect { put "/staff_dashboard/add_users", params: { added_users: visitor.username }, as: :json }.not_to change(LabSession, :count)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "PUT /staff_dashboard/remove_users (sign_out_users)" do
    it "ends the active session now and answers {status: ok}" do
      session_row = sign_in_session(visitor, space)
      freeze_time do
        put "/staff_dashboard/remove_users", params: { dropped_users: [visitor.username] }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json).to eq("status" => "ok")
        expect(session_row.reload.sign_out_time).to eq(Time.zone.now)
      end
      expect(LabSession.active_for_user(visitor)).to be_empty
    end

    it "html: redirects to the dashboard" do
      sign_in_session(visitor, space)
      put "/staff_dashboard/remove_users", params: { dropped_users: [visitor.username] }
      expect(response).to redirect_to(staff_dashboard_index_path)
    end

    it "an unknown username is silently ignored: {status: ok}" do
      put "/staff_dashboard/remove_users", params: { dropped_users: ["nobody"] }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to eq("status" => "ok")
    end

    it "no dropped_users is a no-op {status: ok}" do
      session_row = sign_in_session(visitor, space)
      put "/staff_dashboard/remove_users", as: :json
      expect(json).to eq("status" => "ok")
      expect(session_row.reload.sign_out_time).to be > Time.zone.now
    end

    it "a user who is not signed in anywhere is a 500 (NoMethodError on nil)" do
      # WART(D-STAFF-SIGNOUT-NIL-NEW): `LabSession.active_for_user(user).last.sign_out` has no nil
      # check, so the dashboard's X button for a user whose session expired or was ended in another tab
      # (stale table) gets a 500 instead of {status: "ok"}; the other usernames in the same request
      # are not processed either.
      expect { put "/staff_dashboard/remove_users", params: { dropped_users: [visitor.username] }, as: :json }.not_to change(LabSession, :count)
      expect(response).to have_http_status(:internal_server_error)
      expect(exception_class).to eq("NoMethodError")
    end

    it "a user whose only session already ended is also a 500" do
      # WART(D-STAFF-SIGNOUT-NIL-NEW): same nil dereference.
      ended = create(:lab_session, user: visitor, space: space, sign_in_time: 3.hours.ago, sign_out_time: 1.hour.ago)
      ended_at = ended.reload.sign_out_time
      expect do
        put "/staff_dashboard/remove_users", params: { dropped_users: [visitor.username] }, as: :json
      end.not_to change(LabSession, :count)
      expect(response).to have_http_status(:internal_server_error)
      expect(exception_class).to eq("NoMethodError")
      expect(ended.reload.sign_out_time).to eq(ended_at)
    end

    it "refuses a regular user" do
      session_row = sign_in_session(visitor, space)
      sign_in_as(:regular)
      put "/staff_dashboard/remove_users", params: { dropped_users: [visitor.username] }, as: :json
      expect(response).to redirect_to(root_path)
      expect(session_row.reload.sign_out_time).to be > Time.zone.now
    end
  end

  # WART(D-PERF-NEW2): under CI=1 Bullet raises on the JSON search (`.includes(lab_sessions: :space)`
  # is eager-loaded but `as_json` never reads it: unused eager loading). Pinned with skip_bullet.
  describe "GET /staff_dashboard/search", skip_bullet: true do
    it "answers an array of users carrying name, username and email" do
      target = create(:user, :regular_user, name: "Zelda Findable")

      get "/staff_dashboard/search", params: { query: "Findable" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to be_an(Array)
      entry = json.find { |u| u["id"] == target.id }
      expect(entry).to include("name" => "Zelda Findable", "username" => target.username, "email" => target.email)
      expect(json.map { |u| u["id"] }).to eq([target.id])
    end

    it "matches by email and username fragments, accent- and case-insensitively" do
      target = create(:user, :regular_user, name: "Élodie Rousseau")
      get "/staff_dashboard/search", params: { query: "elodie" }, as: :json
      expect(json.map { |u| u["id"] }).to eq([target.id])
      get "/staff_dashboard/search", params: { query: target.email.upcase }, as: :json
      expect(json.map { |u| u["id"] }).to eq([target.id])
    end

    it "a blank query answers the object {error: 'no params'} (not an array)" do
      get "/staff_dashboard/search", params: { query: "" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to eq("error" => "no params")
    end

    it "does not expose secrets" do
      create(:user, :regular_user, name: "Secret Holder", access_token: "ghp_secret")
      get "/staff_dashboard/search", params: { query: "Secret Holder" }, as: :json
      expect(json.first.keys).not_to include("password", "access_token")
    end
  end

  describe "PUT /staff_dashboard/change_space" do
    it "moves the staff member to the space and answers {status: ok}" do
      put "/staff_dashboard/change_space", params: { space_id: other_space.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to eq("status" => "ok")
      expect(staff.reload.space_id).to eq(other_space.id)
    end

    it "an unknown space_id is a 500 (nil.id)" do
      # WART(D-STAFF-SIGNOUT-NIL-NEW): `new_space.id` is read before the `new_space.present?` check, so an
      # unknown space_id raises instead of answering {status: "error"}.
      put "/staff_dashboard/change_space", params: { space_id: 0 }, as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(exception_class).to eq("NoMethodError")
      expect(staff.reload.space_id).to eq(space.id)
    end
  end
end
