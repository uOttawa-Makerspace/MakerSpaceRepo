# frozen_string_literal: true

require "rails_helper"

# Contract: doc/api/v1/presence.md
RSpec.describe "/api/v1/spaces/:id/presence", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:regular) { create(:user) }
  let!(:space) { create(:space) }
  let!(:other_space) { create(:space) }
  let(:visitor) { create(:user, :regular_user) }

  PRESENCE_USER_KEYS = %w[id username name email flagged avatar_url certifications signed_safety_sheet membership_status].freeze

  def body = response.parsed_body
  def error = body["error"]
  def auth(user) = { "Authorization" => "Bearer #{ApiAccessToken.issue(user).first}" }
  def api_get(path, as: nil) = get(path, headers: json_headers.merge(as ? auth(as) : {}))
  def api_send(verb, path, payload = nil, as: nil) = public_send(verb, path, params: payload&.to_json, headers: json_headers.merge(as ? auth(as) : {}))

  let(:basic_session) { create(:training_session, :basic_training) }

  def certify(user, **extra) = create(:certification, user: user, training_session: basic_session, training: basic_session.training, **extra)

  def in_space(user, target = space, out: 2.hours.from_now)
    create(:lab_session, user: user, space: target, sign_in_time: 1.hour.ago, sign_out_time: out)
  end

  describe "GET /api/v1/spaces/:id/presence" do
    it "401s a guest, 403s a regular user" do
      api_get "/api/v1/spaces/#{space.id}/presence"
      expect(response).to have_http_status(:unauthorized)
      api_get "/api/v1/spaces/#{space.id}/presence", as: regular
      expect(response).to have_http_status(:forbidden)
    end

    it "answers space, users and current_user with exact key sets, for staff and admin" do
      in_space(visitor)
      [staff, admin].each do |caller|
        api_get "/api/v1/spaces/#{space.id}/presence", as: caller
        expect(response).to have_http_status(:ok)
        expect(body.keys).to eq(%w[space users current_user])
        expect(body["space"]).to eq("id" => space.id, "name" => space.name)
        expect(body["current_user"]).to eq("id" => caller.id)
        expect(body["users"].sole.keys).to match_array(PRESENCE_USER_KEYS)
      end
    end

    it "carries the fields the React dashboard reads, and never another user column" do
      visitor.update_columns(access_token: "ghp_secret_token", student_id: "300123456", flagged: true)
      in_space(visitor)
      cert = certify(visitor)
      create(:walk_in_safety_sheet, :is_adult, user: visitor, space: space)
      create(:membership, user: visitor, end_date: 10.days.from_now)

      api_get "/api/v1/spaces/#{space.id}/presence", as: staff

      entry = body["users"].sole
      expect(entry).to include("id" => visitor.id, "username" => visitor.username, "name" => visitor.name,
                               "email" => visitor.email, "flagged" => true,
                               "signed_safety_sheet" => true, "membership_status" => true)
      expect(entry["certifications"]).to eq([{ "id" => cert.id, "name" => cert.training.name_en }])
      expect(entry["avatar_url"]).to end_with("/default-avatar.png")
      expect(response.body).not_to include("ghp_secret_token", "300123456", "access_token", "student_id", "password")
      expect(entry.keys).not_to include("access_token", "student_id", "password", "wallet", "space_id")
    end

    it "reports explicit false and [] for a user with no sheet, membership or certification" do
      in_space(visitor)
      api_get "/api/v1/spaces/#{space.id}/presence", as: staff
      expect(body["users"].sole).to include("signed_safety_sheet" => false, "membership_status" => false, "certifications" => [])
    end

    it "does not count a lapsed, unpaid or future-dated membership" do
      in_space(visitor)
      create(:membership, user: visitor, end_date: 1.day.ago)
      create(:membership, user: visitor, status: "pending", end_date: 10.days.from_now)
      api_get "/api/v1/spaces/#{space.id}/presence", as: staff
      expect(body["users"].sole["membership_status"]).to be(false)
    end

    it "uses the certification's training name, 'Unknown' without one, and only active certifications" do
      in_space(visitor)
      certify(visitor)
      certify(visitor, active: false)
      orphan = certify(visitor)
      orphan.update_columns(training_session_id: nil)
      api_get "/api/v1/spaces/#{space.id}/presence", as: staff
      expect(body["users"].sole["certifications"].map { |c| c["name"] }).to contain_exactly(basic_session.training.name_en, "Unknown")
    end

    it "lists the same users the legacy dashboard does: unexpired sessions in THIS space, once each" do
      here = create(:user, :regular_user)
      twice = create(:user, :regular_user)
      expired = create(:user, :regular_user)
      elsewhere = create(:user, :regular_user)
      gone = create(:user, :regular_user)
      in_space(here)
      in_space(twice)
      in_space(twice, out: 3.hours.from_now)
      in_space(expired, out: 1.minute.ago)
      in_space(elsewhere, other_space)
      in_space(gone)
      gone.update_columns(deleted: true)

      api_get "/api/v1/spaces/#{space.id}/presence", as: staff

      expect(body["users"].map { |u| u["id"] }).to eq([here.id, twice.id].sort)
      expect(body["users"].map { |u| u["id"] }).to match_array(space.signed_in_users.compact.map(&:id))
    end

    it "is empty for an empty space" do
      api_get "/api/v1/spaces/#{other_space.id}/presence", as: staff
      expect(body["users"]).to eq([])
    end

    it "404s an unknown space; a non-numeric id is the router's JSON 404" do
      api_get "/api/v1/spaces/0/presence", as: staff
      expect(response).to have_http_status(:not_found)
      expect(error["code"]).to eq("not_found")
      api_get "/api/v1/spaces/abc/presence", as: staff
      expect(response).to have_http_status(:not_found)
    end

    it "uses a constant number of queries however many users are present (no N+1)" do
      in_space(visitor)
      certify(visitor)
      create(:walk_in_safety_sheet, :is_adult, user: visitor, space: space)
      create(:membership, user: visitor)
      api_get "/api/v1/spaces/#{space.id}/presence", as: staff # warm up
      count = lambda do
        n = 0
        sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| n += 1 unless %w[SCHEMA TRANSACTION].include?(p[:name]) }
        api_get "/api/v1/spaces/#{space.id}/presence", as: staff
        ActiveSupport::Notifications.unsubscribe(sub)
        n
      end
      one = count.call
      4.times do
        u = create(:user, :regular_user)
        in_space(u)
        certify(u)
        create(:walk_in_safety_sheet, :is_adult, user: u, space: space)
        create(:membership, user: u)
      end
      expect(count.call).to eq(one)
      expect(body["users"].size).to eq(5)
    end
  end

  describe "POST /api/v1/spaces/:id/presence" do
    it "401s a guest, 403s a regular user, writing nothing" do
      expect do
        api_send :post, "/api/v1/spaces/#{space.id}/presence", { username: visitor.username }
        expect(response).to have_http_status(:unauthorized)
        api_send :post, "/api/v1/spaces/#{space.id}/presence", { username: visitor.username }, as: regular
        expect(response).to have_http_status(:forbidden)
      end.not_to change(LabSession, :count)
    end

    it "signs the user in for 6 hours, like sign_in_users (staff and admin)" do
      [staff, admin].each_with_index do |caller, i|
        user = [visitor, create(:user, :regular_user)][i]
        freeze_time do
          expect { api_send :post, "/api/v1/spaces/#{space.id}/presence", { username: user.username }, as: caller }
            .to change(LabSession, :count).by(1)
          expect(response).to have_http_status(:no_content)
          expect(response.body).to be_empty
          row = LabSession.where(user: user).sole
          expect(row.space_id).to eq(space.id)
          expect(row.sign_in_time).to eq(Time.zone.now)
          expect(row.sign_out_time).to eq(Time.zone.now + 6.hours)
        end
      end
    end

    it "matches the username case-insensitively" do
      api_send :post, "/api/v1/spaces/#{space.id}/presence", { username: visitor.username.upcase }, as: staff
      expect(response).to have_http_status(:no_content)
      expect(LabSession.where(user: visitor, space: space).active.count).to eq(1)
    end

    it "shows the user in the presence list straight away" do
      api_send :post, "/api/v1/spaces/#{space.id}/presence", { username: visitor.username }, as: staff
      api_get "/api/v1/spaces/#{space.id}/presence", as: staff
      expect(body["users"].map { |u| u["username"] }).to eq([visitor.username])
    end

    it "is idempotent: a user already in the space gets no second session (DEVIATION: legacy added a row each time)" do
      session = in_space(visitor)
      expect { api_send :post, "/api/v1/spaces/#{space.id}/presence", { username: visitor.username }, as: staff }
        .not_to change(LabSession, :count)
      expect(response).to have_http_status(:no_content)
      expect(session.reload.sign_out_time).to be > 1.hour.from_now
    end

    it "signs in again when the earlier session expired, and when the user is in another space" do
      in_space(visitor, space, out: 1.minute.ago)
      in_space(visitor, other_space)
      expect { api_send :post, "/api/v1/spaces/#{space.id}/presence", { username: visitor.username }, as: staff }
        .to change { LabSession.where(user: visitor, space: space).active.count }.from(0).to(1)
      expect(LabSession.where(user: visitor, space: other_space).active.count).to eq(1)
    end

    it "404s an unknown or soft-deleted user and an unknown space, writing nothing" do
      gone = create(:user, :regular_user)
      gone.update_columns(deleted: true)
      expect do
        api_send :post, "/api/v1/spaces/#{space.id}/presence", { username: "nobodyhere" }, as: staff
        expect(response).to have_http_status(:not_found)
        api_send :post, "/api/v1/spaces/#{space.id}/presence", { username: gone.username }, as: staff
        expect(response).to have_http_status(:not_found)
        api_send :post, "/api/v1/spaces/#{space.id}/presence", { username: "a\u0000b" }, as: staff
        expect(response).to have_http_status(:not_found)
        api_send :post, "/api/v1/spaces/0/presence", { username: visitor.username }, as: staff
        expect(response).to have_http_status(:not_found)
        expect(error["code"]).to eq("not_found")
      end.not_to change(LabSession, :count)
    end

    it "422s a missing username" do
      api_send :post, "/api/v1/spaces/#{space.id}/presence", {}, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("parameter_missing")
      expect(LabSession.count).to eq(0)
    end
  end

  describe "DELETE /api/v1/spaces/:id/presence/:username" do
    it "401s a guest, 403s a regular user, ending nothing" do
      session = in_space(visitor)
      api_send :delete, "/api/v1/spaces/#{space.id}/presence/#{visitor.username}"
      expect(response).to have_http_status(:unauthorized)
      api_send :delete, "/api/v1/spaces/#{space.id}/presence/#{visitor.username}", as: regular
      expect(response).to have_http_status(:forbidden)
      expect(session.reload.sign_out_time).to be > 1.hour.from_now
    end

    it "ends the active session now, like sign_out_users (staff and admin)" do
      [staff, admin].each do |caller|
        user = create(:user, :regular_user)
        session = in_space(user)
        freeze_time do
          api_send :delete, "/api/v1/spaces/#{space.id}/presence/#{user.username}", as: caller
          expect(response).to have_http_status(:no_content)
          expect(response.body).to be_empty
          expect(session.reload.sign_out_time).to eq(Time.zone.now)
        end
        expect(LabSession.active_for_user(user)).to be_empty
      end
    end

    it "drops the user from the presence list" do
      in_space(visitor)
      api_send :delete, "/api/v1/spaces/#{space.id}/presence/#{visitor.username}", as: staff
      api_get "/api/v1/spaces/#{space.id}/presence", as: staff
      expect(body["users"]).to eq([])
    end

    it "ends every active session in THIS space only (DEVIATION: legacy ended the latest one in any space)" do
      a = in_space(visitor)
      b = in_space(visitor, space, out: 3.hours.from_now)
      elsewhere = in_space(visitor, other_space)
      api_send :delete, "/api/v1/spaces/#{space.id}/presence/#{visitor.username}", as: staff
      expect([a, b].map { |s| s.reload.sign_out_time }).to all(be <= Time.zone.now)
      expect(elsewhere.reload.sign_out_time).to be > 1.hour.from_now
    end

    it "is idempotent: a user who is not in the space is a 204 and nothing changes (DEVIATION: legacy 500)" do
      ended = create(:lab_session, user: visitor, space: space, sign_in_time: 3.hours.ago, sign_out_time: 1.hour.ago)
      stamp = ended.reload.sign_out_time
      expect { api_send :delete, "/api/v1/spaces/#{space.id}/presence/#{visitor.username}", as: staff }.not_to change(LabSession, :count)
      expect(response).to have_http_status(:no_content)
      expect(ended.reload.sign_out_time).to eq(stamp)
    end

    it "matches the username case-insensitively and accepts percent-encoded accents" do
      accented = create(:user, :regular_user, username: "josé1")
      in_space(accented)
      api_send :delete, "/api/v1/spaces/#{space.id}/presence/#{ERB::Util.url_encode('JOSÉ1')}", as: staff
      expect(response).to have_http_status(:no_content)
      expect(LabSession.active_for_user(accented)).to be_empty
    end

    it "404s an unknown user or space" do
      api_send :delete, "/api/v1/spaces/#{space.id}/presence/nobodyhere", as: staff
      expect(response).to have_http_status(:not_found)
      api_send :delete, "/api/v1/spaces/0/presence/#{visitor.username}", as: staff
      expect(response).to have_http_status(:not_found)
      expect(error["code"]).to eq("not_found")
    end
  end
end
