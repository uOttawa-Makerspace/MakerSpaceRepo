# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/v1/session", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "asa32A353#" }
  let(:user) { create(:user) }
  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }

  # methods, not lets: one example makes several requests
  def body = response.parsed_body
  def error = body["error"]

  def api_post(path, payload, headers = {})
    post path, params: payload.to_json, headers: json_headers.merge(headers)
  end

  def login(u = user, pw: password)
    api_post "/api/v1/session", { login: u.username, password: pw }
  end

  def bearer(token) = { "Authorization" => "Bearer #{token}" }

  describe "POST /api/v1/session" do
    it "201s with a token pair and the allowlisted user" do
      freeze_time do
        login
        expect(response).to have_http_status(:created)
        expect(body.keys).to match_array(%w[access_token access_token_expires_at refresh_token user])
        expect(body["user"]).to eq("id" => user.id, "username" => user.username, "name" => user.name, "role" => "regular_user")
        expect(Time.zone.parse(body["access_token_expires_at"])).to eq(15.minutes.from_now.change(usec: 0))

        payload, = JWT.decode(body["access_token"], ApiAccessToken.secret, true, algorithm: "HS256")
        expect(payload).to include("user_id" => user.id, "ver" => user.token_version, "typ" => "access", "exp" => 15.minutes.from_now.to_i)
      end
    end

    it "stores only the digest of the refresh token and the user agent" do
      login
      record = ApiRefreshToken.find_by!(token_digest: ApiRefreshToken.digest(body["refresh_token"]))
      expect(record.user_id).to eq(user.id)
      expect(ApiRefreshToken.pluck(:token_digest)).not_to include(body["refresh_token"])
    end

    it "accepts the email as the login, case-insensitively" do
      api_post "/api/v1/session", { login: user.email.upcase, password: password }
      expect(response).to have_http_status(:created)
    end

    it "does not leak secrets or write a cookie/session" do
      login
      expect(response.body).not_to include("password", "access_token\":null")
      expect(body["user"].keys).to match_array(%w[id username name role])
      expect(response.headers["Set-Cookie"]).to be_nil
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    it "records last_signed_in_time and resets the failed-attempt counter" do
      user.update_columns(auth_attempts: 3)
      login
      expect(user.reload.auth_attempts).to eq(0)
      expect(user.last_signed_in_time).to be_present
    end

    it "401s a wrong password and counts the attempt" do
      login(pw: "wrong")
      expect(response).to have_http_status(:unauthorized)
      expect(error).to eq("code" => "invalid_credentials", "message" => "Invalid login or password")
      expect(user.reload.auth_attempts).to eq(1)
    end

    it "answers an unknown login exactly like a wrong password" do
      api_post "/api/v1/session", { login: "nobody-here", password: "x" }
      expect(response).to have_http_status(:unauthorized)
      expect(error["code"]).to eq("invalid_credentials")
      expect(error["message"]).to eq("Invalid login or password")
    end

    it "423s the attempt that trips the lockout, then rejects even the right password" do
      user.update_columns(auth_attempts: 4)
      login(pw: "wrong")
      expect(response).to have_http_status(:locked)
      expect(error["code"]).to eq("account_locked")
      expect(user.reload.locked).to be(true)

      login
      expect(response).to have_http_status(:locked)
      expect(error["message"]).to include("locked").and include("or wait")
      expect(error["support_email"]).to eq(SessionsController::SUPPORT_EMAIL)
      expect(ApiRefreshToken.count).to eq(0)
    end

    it "423s an admin lock without a wait suffix" do
      user.admin_lock!
      login
      expect(response).to have_http_status(:locked)
      expect(error["message"]).not_to include("or wait")
    end

    it "lets the user in once a timed lockout has lapsed" do
      user.update_columns(locked: true, locked_until: 1.minute.ago, auth_attempts: 5)
      login
      expect(response).to have_http_status(:created)
      expect(user.reload.locked).to be(false)
    end

    it "403s an unconfirmed account" do
      unconfirmed = create(:user, :regular_user_not_confirmed)
      login(unconfirmed)
      expect(response).to have_http_status(:forbidden)
      expect(error["code"]).to eq("account_unconfirmed")
    end

    it "403s an inactive account" do
      User.unscoped.where(id: user.id).update_all(deactivated_at: Time.current)
      login
      expect(response).to have_http_status(:forbidden)
      expect(error["code"]).to eq("account_inactive")
      expect(error["message"]).to eq("This account has been deactivated. Please contact #{SessionsController::SUPPORT_EMAIL}.")
      expect(error["support_email"]).to be_present
    end

    it "does not sign in a soft-deleted account" do
      user.soft_delete!
      login
      expect(response).to have_http_status(:unauthorized)
    end

    it "422s missing fields" do
      api_post "/api/v1/session", { login: user.username }
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["fields"]).to eq("password" => ["is required"])
    end

    it "does not need or touch a CSRF token or cookies (forgery protection is on in the test env)" do
      expect(ActionController::Base.allow_forgery_protection).to be(true)
      login
      expect(response).to have_http_status(:created)
    end

    describe "rate limit" do
      let(:counts) { Hash.new(0) }

      before { allow(RateLimitCounter).to receive(:increment) { |key, *| counts[key] += 1 } }

      it "429s after 10 attempts in the shared password-sign-in budget" do
        10.times { api_post "/api/v1/session", { login: "nobody-here", password: "x" } }
        expect(response).to have_http_status(:unauthorized)
        login
        expect(response).to have_http_status(:too_many_requests)
        expect(error["code"]).to eq("rate_limited")
      end

      it "shares the budget (same cache key) with the legacy login and SAML" do
        10.times { post login_authentication_path, params: { username_email: "nobody-here", password: "x" }, as: :json }
        login
        expect(response).to have_http_status(:too_many_requests)
        expect(counts.keys.grep(/password-sign-in/).size).to eq(1)
      end
    end

    it "keeps the legacy login unchanged" do
      post login_authentication_path, params: { username_email: user.username, password: password }, as: :json
      expect(response).to have_http_status(:ok)
      expect(body.keys).to include("user", "signed_in", "token")
    end
  end

  describe "GET /api/v1/session" do
    let(:access) { ApiAccessToken.issue(user).first }

    it "returns the user for a valid access token and issues nothing" do
      get "/api/v1/session", headers: bearer(access)
      expect(response).to have_http_status(:ok)
      expect(body).to eq("user" => { "id" => user.id, "username" => user.username, "name" => user.name, "role" => "regular_user" })
      expect(response.headers["Set-Cookie"]).to be_nil
      expect(ApiRefreshToken.count).to eq(0)
    end

    it "401s without or with an invalid token" do
      get "/api/v1/session"
      expect(response).to have_http_status(:unauthorized)
      get "/api/v1/session", headers: bearer("junk")
      expect(response).to have_http_status(:unauthorized)
      expect(error["code"]).to eq("unauthenticated")
    end

    it "401s an expired access token" do
      jwt = nil
      travel_to(16.minutes.ago) { jwt = ApiAccessToken.issue(user).first }
      get "/api/v1/session", headers: bearer(jwt)
      expect(response).to have_http_status(:unauthorized)
    end

    it "401s the legacy token and a token with the wrong scheme" do
      get "/api/v1/session", headers: bearer(user.token)
      expect(response).to have_http_status(:unauthorized)
      get "/api/v1/session", headers: { "Authorization" => "Token #{access}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "does not honor a legacy cookie session" do
      post login_authentication_path, params: { username_email: user.username, password: password }
      get "/api/v1/session"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/session/refresh" do
    before { login }

    let(:first_refresh) { body["refresh_token"] }

    def refresh(token) = api_post("/api/v1/session/refresh", { refresh_token: token })

    it "rotates: a new pair, and the old refresh token is dead" do
      old = first_refresh
      old_access = body["access_token"]
      refresh(old)
      expect(response).to have_http_status(:ok)
      expect(body.keys).to match_array(%w[access_token access_token_expires_at refresh_token user])
      expect(body["refresh_token"]).not_to eq(old)
      get "/api/v1/session", headers: bearer(body["access_token"])
      expect(response).to have_http_status(:ok)
      expect(old_access).to be_present
    end

    it "answers a replay within 30 seconds with 409 refresh_in_progress and revokes nothing" do
      old = first_refresh
      refresh(old)
      newest = body["refresh_token"]

      travel_to(29.seconds.from_now) { refresh(old) }
      expect(response).to have_http_status(:conflict)
      expect(error["code"]).to eq("refresh_in_progress")
      expect(response.body).not_to include("refresh_token\":")

      refresh(newest) # the retry with the newly stored token works
      expect(response).to have_http_status(:ok)
    end

    it "treats reuse of a rotated token after 30 seconds as theft: 401 and the whole family is revoked" do
      old = first_refresh
      refresh(old)
      newest = body["refresh_token"]

      travel_to(31.seconds.from_now) { refresh(old) }
      expect(response).to have_http_status(:unauthorized)
      expect(error["code"]).to eq("invalid_refresh_token")

      refresh(newest)
      expect(response).to have_http_status(:unauthorized)
    end

    it "does not touch other devices' families on reuse" do
      other = user.then { |u| ApiRefreshToken.issue!(u) }
      old = first_refresh
      refresh(old)
      travel_to(31.seconds.from_now) { refresh(old) }
      refresh(other.raw_token)
      expect(response).to have_http_status(:ok)
    end

    it "401s an unknown token" do
      refresh("nope")
      expect(response).to have_http_status(:unauthorized)
    end

    it "401s an expired token" do
      travel_to(31.days.from_now) { refresh(first_refresh) }
      expect(response).to have_http_status(:unauthorized)
    end

    it "401s for an account that became inactive or deleted" do
      User.unscoped.where(id: user.id).update_all(deactivated_at: Time.current)
      refresh(first_refresh)
      expect(response).to have_http_status(:unauthorized)
    end

    it "422s a missing token and 401s a non-string one" do
      api_post "/api/v1/session/refresh", {}
      expect(response).to have_http_status(:unprocessable_content)
      api_post "/api/v1/session/refresh", { refresh_token: { a: 1 } }
      expect(response).to have_http_status(:unauthorized)
    end

    it "does not accept an access token as a refresh token" do
      refresh(body["access_token"])
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/session" do
    before { login }

    it "revokes the family (body token), 204, and is idempotent" do
      refresh = body["refresh_token"]
      api_post "/api/v1/session/refresh", { refresh_token: refresh }
      newest = body["refresh_token"]

      delete "/api/v1/session", params: { refresh_token: newest }.to_json, headers: json_headers
      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
      expect(ApiRefreshToken.where(family_id: ApiRefreshToken.first.family_id).where(revoked_at: nil)).to be_empty

      delete "/api/v1/session", params: { refresh_token: newest }.to_json, headers: json_headers
      expect(response).to have_http_status(:no_content)

      api_post "/api/v1/session/refresh", { refresh_token: newest }
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts the token in the X-Refresh-Token header" do
      token = body["refresh_token"]
      delete "/api/v1/session", headers: { "X-Refresh-Token" => token }
      expect(response).to have_http_status(:no_content)
      expect(ApiRefreshToken.where(revoked_at: nil)).to be_empty
    end

    it "204s with no token or an unknown one, and revokes nothing" do
      delete "/api/v1/session"
      expect(response).to have_http_status(:no_content)
      delete "/api/v1/session", params: { refresh_token: "unknown" }.to_json, headers: json_headers
      expect(response).to have_http_status(:no_content)
      expect(ApiRefreshToken.where(revoked_at: nil).count).to eq(1)
    end

    it "leaves the user's other devices signed in" do
      first = body["refresh_token"]
      login
      second = body["refresh_token"]
      delete "/api/v1/session", params: { refresh_token: first }.to_json, headers: json_headers
      api_post "/api/v1/session/refresh", { refresh_token: second }
      expect(response).to have_http_status(:ok)
    end
  end
end
