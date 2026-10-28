# frozen_string_literal: true

require "rails_helper"

# Contract: doc/api/v1/users.md
RSpec.describe "/api/v1/users", type: :request do
  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:regular) { create(:user) }
  let(:target) { create(:user) }

  def body = response.parsed_body
  def error = body["error"]
  def auth(user) = { "Authorization" => "Bearer #{ApiAccessToken.issue(user).first}" }
  def api_get(path, as: nil, params: {}) = get(path, params: params, headers: json_headers.merge(as ? auth(as) : {}))

  def api_send(verb, path, payload, as: nil)
    public_send(verb, path, params: payload.to_json, headers: json_headers.merge(as ? auth(as) : {}))
  end

  PROFILE_USER_KEYS = %w[id username name email faculty program year_of_study identity role avatar_url rfid].freeze

  describe "GET /api/v1/users/:username" do
    let!(:training) { create(:training) }

    it "401s without a token" do
      api_get "/api/v1/users/#{target.username}"
      expect(response).to have_http_status(:unauthorized)
      expect(error["code"]).to eq("unauthenticated")
      expect(response.headers["WWW-Authenticate"]).to include("Bearer")
    end

    it "403s a regular user asking for someone else, whether or not that user exists" do
      api_get "/api/v1/users/#{target.username}", as: regular
      expect(response).to have_http_status(:forbidden)
      expect(error["code"]).to eq("forbidden")
      api_get "/api/v1/users/nobodyhere", as: regular
      expect(response).to have_http_status(:forbidden)
    end

    it "lets a regular user read their own profile (any username casing)" do
      api_get "/api/v1/users/#{regular.username.upcase}", as: regular
      expect(response).to have_http_status(:ok)
      expect(body["user"]["id"]).to eq(regular.id)
    end

    it "does not let a user read another account whose name only matches under Unicode case folding (maßen vs massen)" do
      folded = create(:user, username: "maßen")
      victim = create(:user, username: "massen")
      api_get "/api/v1/users/massen", as: folded
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include(victim.email)
      api_get "/api/v1/users/#{ERB::Util.url_encode("maßen")}", as: folded
      expect(response).to have_http_status(:ok)
      expect(body["user"]["id"]).to eq(folded.id)
    end

    it "lets staff and admin read anyone" do
      api_get "/api/v1/users/#{target.username}", as: staff
      expect(response).to have_http_status(:ok)
      api_get "/api/v1/users/#{target.username}", as: admin
      expect(response).to have_http_status(:ok)
    end

    it "returns exactly the allowlisted key set and no secrets" do
      create(:rfid, user: target, card_number: "CARD123")
      api_get "/api/v1/users/#{target.username}", as: staff
      expect(body.keys).to match_array(%w[user programs certifications remaining_trainings])
      expect(body["user"].keys).to match_array(PROFILE_USER_KEYS)
      expect(body["user"]["rfid"]).to eq("card_number" => "CARD123")
      expect(body["user"]).to include("id" => target.id, "username" => target.username, "email" => target.email, "role" => "regular_user")
      expect(response.body).not_to match(/password|access_token|student_id|wallet|mac_address/)
    end

    it "has rfid null when no card is linked" do
      api_get "/api/v1/users/#{target.username}", as: staff
      expect(body["user"]["rfid"]).to be_nil
    end

    it "builds avatar_url from the default image when no avatar is attached" do
      api_get "/api/v1/users/#{target.username}", as: staff
      expect(body["user"]["avatar_url"]).to eq("http://www.example.com/default-avatar.png")
    end

    it "builds avatar_url from the Active Storage blob when an avatar is attached" do
      with_avatar = create(:user, :regular_user_with_avatar)
      api_get "/api/v1/users/#{with_avatar.username}", as: staff
      url = body["user"]["avatar_url"]
      expect(url).to start_with("http://www.example.com/rails/active_storage/blobs/")
      expect(url).to end_with("/avatar.png")
      get url
      expect(response.status).to be_between(200, 399) # the blob URL resolves (redirect or proxy)
    end

    it "lists programs, certifications (id, updated_at, training{id,name_en}) and remaining_trainings" do
      cert = create(:certification, :"3d_printing", user: target)
      target.programs.create!(program_type: Program::VOLUNTEER)
      remaining = create(:training, name_en: "Left over")
      api_get "/api/v1/users/#{target.username}", as: staff
      expect(body["programs"]).to eq([Program::VOLUNTEER])
      expect(body["certifications"].size).to eq(1)
      c = body["certifications"].first
      expect(c.keys).to match_array(%w[id updated_at training])
      expect(c["id"]).to eq(cert.id)
      expect(c["training"].keys).to match_array(%w[id name_en])
      expect(c["training"]["id"]).to eq(cert.training.id)
      expect(body["remaining_trainings"].map { |t| t["id"] }).to include(remaining.id)
      expect(body["remaining_trainings"].map { |t| t["id"] }).not_to include(cert.training.id)
      expect(body["remaining_trainings"].first.keys).to match_array(%w[id name_en])
    end

    it "does not 500 on certifications without a training session (proficient-project or orphaned) and counts their training as held" do
      pp = create(:proficient_project)
      pp_cert = create(:certification, user: target, training_session: nil)
      create(:proficient_project_session, certification: pp_cert, user: target, proficient_project: pp, level: "Beginner")
      create(:certification, user: target, training_session: nil) # orphan: no session of any kind
      other = create(:training, name_en: "Untouched")
      api_get "/api/v1/users/#{target.username}", as: staff
      expect(response).to have_http_status(:ok)
      ids = body["remaining_trainings"].map { |t| t["id"] }
      expect(ids).to include(other.id)
      expect(ids).not_to include(pp.training_id)
    end

    it "404s an unknown username for staff" do
      api_get "/api/v1/users/nobodyhere", as: staff
      expect(response).to have_http_status(:not_found)
      expect(error["code"]).to eq("not_found")
    end

    it "lets staff open a soft-deleted user, like the legacy profile" do
      target.soft_delete!
      api_get "/api/v1/users/#{target.username}", as: staff
      expect(response).to have_http_status(:ok)
    end

    it "finds a URL-encoded username with accented characters (usernames are letters, digits, accents only)" do
      accented = create(:user, username: "josé1")
      api_get "/api/v1/users/#{ERB::Util.url_encode(accented.username)}", as: staff
      expect(response).to have_http_status(:ok)
      expect(body["user"]["username"]).to eq("josé1")
    end

    it "does not treat a dot as a format suffix" do
      api_get "/api/v1/users/#{target.username}.json", as: staff
      expect(response).to have_http_status(:not_found)
      expect(error["code"]).to eq("not_found")
    end
  end

  describe "GET /api/v1/users?query=" do
    it "401s without a token and 403s a regular user" do
      api_get "/api/v1/users", params: { query: "ab" }
      expect(response).to have_http_status(:unauthorized)
      api_get "/api/v1/users", as: regular, params: { query: "ab" }
      expect(response).to have_http_status(:forbidden)
    end

    it "returns the allowlisted keys only, matching name, email or username, accent-insensitively" do
      match = create(:user, name: "Zoë Quartz", username: "zq1", email: "zq1@example.com")
      create(:user, name: "Other Person")
      api_get "/api/v1/users", as: staff, params: { query: "zoe qua" }
      expect(response).to have_http_status(:ok)
      expect(body.keys).to match_array(%w[users meta])
      expect(body["users"].map { |u| u["id"] }).to eq([match.id])
      expect(body["users"].first.keys).to match_array(%w[id username name email avatar_url])
      expect(body["users"].first["avatar_url"]).to end_with("/default-avatar.png")
      expect(body["meta"]).to eq("limit" => 50, "truncated" => false)
      api_get "/api/v1/users", as: admin, params: { query: "ZQ1@EXAMPLE" }
      expect(body["users"].map { |u| u["id"] }).to eq([match.id])
      expect(response.body).not_to match(/password|access_token|student_id/)
    end

    it "treats LIKE wildcards literally" do
      create(:user, name: "Plain Name")
      api_get "/api/v1/users", as: staff, params: { query: "%%" }
      expect(body["users"]).to eq([])
    end

    it "422s a query shorter than 2 characters (after trimming) and a missing one" do
      api_get "/api/v1/users", as: staff, params: { query: " a " }
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("validation_failed")
      expect(error["fields"]).to have_key("query")
      api_get "/api/v1/users", as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("parameter_missing")
    end

    it "caps the result and flags truncation" do
      stub_const("Api::V1::UsersController::SEARCH_LIMIT", 2)
      3.times { |i| create(:user, name: "Bulk Match #{i}") }
      api_get "/api/v1/users", as: staff, params: { query: "Bulk Match" }
      expect(body["users"].size).to eq(2)
      expect(body["meta"]).to eq("limit" => 2, "truncated" => true)
    end

    it "keeps the most recently active users when truncating (updated_at DESC)" do
      stub_const("Api::V1::UsersController::SEARCH_LIMIT", 2)
      oldest = create(:user, name: "Recent Match A")
      middle = create(:user, name: "Recent Match B")
      newest = create(:user, name: "Recent Match C")
      oldest.update_column(:updated_at, 3.days.ago)
      middle.update_column(:updated_at, 2.days.ago)
      newest.update_column(:updated_at, 1.day.ago)
      api_get "/api/v1/users", as: staff, params: { query: "Recent Match" }
      expect(body["users"].map { |u| u["id"] }).to eq([newest.id, middle.id])
      expect(body["meta"]["truncated"]).to be(true)
    end

    it "422s a query longer than 100 characters, and accepts exactly 100" do
      api_get "/api/v1/users", as: staff, params: { query: "a" * 101 }
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["fields"]["query"].first).to include("too long")
      api_get "/api/v1/users", as: staff, params: { query: "a" * 100 }
      expect(response).to have_http_status(:ok)
    end

    describe "rate limit" do
      let(:counts) { Hash.new(0) }

      before { allow(Api::V1::UsersController.cache_store).to receive(:increment) { |key, *| counts[key] += 1 } }

      it "429s the 61st search in a minute, per user" do
        60.times { api_get "/api/v1/users", as: staff, params: { query: "zz" } }
        expect(response).to have_http_status(:ok)
        api_get "/api/v1/users", as: staff, params: { query: "zz" }
        expect(response).to have_http_status(:too_many_requests)
        expect(error["code"]).to eq("rate_limited")
        api_get "/api/v1/users", as: admin, params: { query: "zz" }
        expect(response).to have_http_status(:ok)
      end

      it "does not count unauthenticated requests" do
        61.times { api_get "/api/v1/users", params: { query: "zz" } }
        expect(response).to have_http_status(:unauthorized)
        expect(counts).to be_empty
      end
    end
  end

  describe "PATCH /api/v1/users/:id/role" do
    it "401s without a token" do
      api_send :patch, "/api/v1/users/#{target.id}/role", { role: "staff" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "403s staff, regular users and self-promotion" do
      [staff, regular].each do |caller|
        api_send :patch, "/api/v1/users/#{target.id}/role", { role: "staff" }, as: caller
        expect(response).to have_http_status(:forbidden)
      end
      api_send :patch, "/api/v1/users/#{regular.id}/role", { role: "admin" }, as: regular
      expect(response).to have_http_status(:forbidden)
      expect(regular.reload.role).to eq("regular_user")
      expect(target.reload.role).to eq("regular_user")
    end

    it "lets an admin change another user's role (204, empty body)" do
      api_send :patch, "/api/v1/users/#{target.id}/role", { role: "staff" }, as: admin
      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
      expect(target.reload.role).to eq("staff")
      api_send :patch, "/api/v1/users/#{target.id}/role", { role: "regular_user" }, as: admin
      expect(target.reload.role).to eq("regular_user")
    end

    it "lets an admin demote themself while another usable admin exists" do
      create(:user, :admin)
      api_send :patch, "/api/v1/users/#{admin.id}/role", { role: "staff" }, as: admin
      expect(response).to have_http_status(:no_content)
      expect(admin.reload.role).to eq("staff")
    end

    it "refuses to remove the last admin (422 last_admin), also when the other admin is locked" do
      api_send :patch, "/api/v1/users/#{admin.id}/role", { role: "regular_user" }, as: admin
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("last_admin")
      expect(error["fields"]).to have_key("role")
      expect(admin.reload.role).to eq("admin")

      create(:user, :admin).admin_lock!
      api_send :patch, "/api/v1/users/#{admin.id}/role", { role: "staff" }, as: admin
      expect(response).to have_http_status(:unprocessable_content)
      expect(admin.reload.role).to eq("admin")
    end

    it "disconnects the demoted user's cable connections after commit (change_role! semantics)" do
      create(:user, :admin)
      target.change_role!("staff")
      expect(ActionCable.server.remote_connections).to receive(:where).with(current_user: target).and_call_original
      api_send :patch, "/api/v1/users/#{target.id}/role", { role: "regular_user" }, as: admin
      expect(response).to have_http_status(:no_content)
    end

    it "422s a missing, unknown or unassignable role" do
      api_send :patch, "/api/v1/users/#{target.id}/role", {}, as: admin
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("parameter_missing")
      %w[superuser volunteer].push(["admin"], 5).each do |bad|
        api_send :patch, "/api/v1/users/#{target.id}/role", { role: bad }, as: admin
        expect(response).to have_http_status(:unprocessable_content)
        expect(error["code"]).to eq("validation_failed")
        expect(error["fields"]).to have_key("role")
      end
      expect(target.reload.role).to eq("regular_user")
    end

    it "404s an unknown or soft-deleted user" do
      api_send :patch, "/api/v1/users/0/role", { role: "staff" }, as: admin
      expect(response).to have_http_status(:not_found)
      api_send :patch, "/api/v1/users/abc/role", { role: "staff" }, as: admin
      expect(response).to have_http_status(:not_found)
      target.soft_delete!
      api_send :patch, "/api/v1/users/#{target.id}/role", { role: "staff" }, as: admin
      expect(response).to have_http_status(:not_found)
    end

    it "400s malformed JSON" do
      patch "/api/v1/users/#{target.id}/role", params: "{oops", headers: json_headers.merge(auth(admin))
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "PUT /api/v1/users/:id/programs" do
    it "401s without a token and 403s a regular user, even for themself" do
      api_send :put, "/api/v1/users/#{target.id}/programs", { development: true, volunteer: true }
      expect(response).to have_http_status(:unauthorized)
      api_send :put, "/api/v1/users/#{regular.id}/programs", { development: true, volunteer: true }, as: regular
      expect(response).to have_http_status(:forbidden)
      expect(regular.programs).to be_empty
    end

    it "replaces the dev and volunteer memberships and returns exactly programs[]" do
      api_send :put, "/api/v1/users/#{target.id}/programs", { development: true, volunteer: true }, as: staff
      expect(response).to have_http_status(:ok)
      expect(body.keys).to eq(["programs"])
      expect(body["programs"]).to match_array([Program::DEV_PROGRAM, Program::VOLUNTEER])

      api_send :put, "/api/v1/users/#{target.id}/programs", { development: false, volunteer: true }, as: admin
      expect(body["programs"]).to eq([Program::VOLUNTEER])
      expect(target.programs.pluck(:program_type)).to eq([Program::VOLUNTEER])
    end

    it "is idempotent and leaves the teams program alone" do
      target.programs.create!(program_type: Program::TEAMS)
      2.times { api_send :put, "/api/v1/users/#{target.id}/programs", { development: true, volunteer: false }, as: staff }
      expect(body["programs"]).to match_array([Program::TEAMS, Program::DEV_PROGRAM])
    end

    it "lets staff change their own programs" do
      api_send :put, "/api/v1/users/#{staff.id}/programs", { development: true, volunteer: false }, as: staff
      expect(body["programs"]).to eq([Program::DEV_PROGRAM])
    end

    it "422s a missing flag and non-boolean values, changing nothing" do
      api_send :put, "/api/v1/users/#{target.id}/programs", { development: true }, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("parameter_missing")
      expect(error["fields"]).to have_key("volunteer")
      api_send :put, "/api/v1/users/#{target.id}/programs", { development: "yes", volunteer: nil }, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("validation_failed")
      expect(error["fields"].keys).to match_array(%w[development volunteer])
      expect(target.programs).to be_empty
    end

    it "404s an unknown or soft-deleted user" do
      api_send :put, "/api/v1/users/0/programs", { development: true, volunteer: true }, as: staff
      expect(response).to have_http_status(:not_found)
      target.soft_delete!
      api_send :put, "/api/v1/users/#{target.id}/programs", { development: true, volunteer: true }, as: staff
      expect(response).to have_http_status(:not_found)
    end
  end

  it "404s ids that are only a numeric prefix (12abc is not 12), for role and programs" do
    api_send :patch, "/api/v1/users/#{target.id}abc/role", { role: "staff" }, as: admin
    expect(response).to have_http_status(:not_found)
    api_send :put, "/api/v1/users/#{target.id}x/programs", { development: true, volunteer: true }, as: staff
    expect(response).to have_http_status(:not_found)
    api_send :put, "/api/v1/users/#{target.id}.5/programs", { development: true, volunteer: true }, as: staff
    expect(response).to have_http_status(:not_found)
    expect(target.reload.role).to eq("regular_user")
    expect(target.programs).to be_empty
  end

  it "answers every response with Cache-Control no-store and no cookie" do
    api_get "/api/v1/users/#{target.username}", as: staff
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "refuses a deactivated caller" do
    token = auth(staff)
    staff.update_column(:active, false)
    get "/api/v1/users/#{target.username}", headers: json_headers.merge(token)
    expect(response).to have_http_status(:unauthorized)
  end
end
