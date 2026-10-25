# frozen_string_literal: true

require "rails_helper"

# Characterization spec for SessionsController (chunk 9 "Identity").
# Pins login failure, lockout, expiry and last_seen_at as they behave today.
# Defects are PINNED, not fixed.
#
# Environment notes:
# * Auth is a custom cookie session (no Devise); expiry is driven with time travel.
# * test env uses :null_store, so `rate_limit` on login_authentication never
#   throttles here (not pinnable without changing config).
# * Net::HTTP is blocked (ShopSpecHelpers) so no external call can slip through.

RSpec.describe "Sessions (HTTP contract)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "asa32A353#" }
  let(:user) { create(:user, :regular_user) }

  before { block_external_http! }

  def login!(u, pw: password)
    post login_authentication_path, params: { username_email: u.username, password: pw }
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  describe "GET /login" do
    it "renders the form for a guest" do
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("username_email")
    end

    it "redirects a signed-in user to root" do
      login!(user)
      get login_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /login_authentication (success)" do
    it "signs in by username and redirects to root" do
      login!(user)
      expect(response).to redirect_to(root_path)
      get check_signed_in_path
      expect(JSON.parse(response.body)["signed_in"]).to eq("true")
    end

    it "signs in by email, case-insensitively" do
      post login_authentication_path,
           params: { username_email: user.email.upcase, password: password }
      expect(response).to redirect_to(root_path)
    end

    it "honours a relative back_to" do
      post login_authentication_path,
           params: { username_email: user.username, password: password, back_to: "/lockers" }
      expect(response).to redirect_to("/lockers")
    end

    it "an external back_to is refused by Rails' open-redirect guard (500, UnsafeRedirectError)" do
      # Not a defect in the app's own code: Rails 7+ raise_on_open_redirects turns it into an error page. The 500 (instead of a clean fallback to root) is cosmetic.
      post login_authentication_path,
           params: { username_email: user.username, password: password, back_to: "https://evil.example/phish" }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "sets last_signed_in_time and resets auth_attempts" do
      user.update_columns(auth_attempts: 3)
      login!(user)
      user.reload
      expect(user.auth_attempts).to eq(0)
      expect(user.last_signed_in_time).to be_within(1.minute).of(Time.current)
    end

    it "returns user json plus a JWT token for json requests" do
      post login_authentication_path,
           params: { username_email: user.username, password: password },
           as: :json
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body["signed_in"]).to eq(true)
      expect(body["token"]).to be_present
      expect(body["user"]["username"]).to eq(user.username)
    end

    it "leaks the password hash in the json user payload" do
      # WART(D-I02): login/check_signed_in JSON serialises the whole user incl. the bcrypt `password` column
      post login_authentication_path,
           params: { username_email: user.username, password: password },
           as: :json
      expect(JSON.parse(response.body)["user"]).to include("password")
    end
  end

  describe "POST /login_authentication (failure)" do
    it "unknown user: 422 + flash naming the identifier" do
      post login_authentication_path, params: { username_email: "nobody", password: "x" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("Could not find user with email or username: nobody")
    end

    it "unknown user json" do
      post login_authentication_path,
           params: { username_email: "nobody", password: "x" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to eq(
        "error" => "Could not find user with email or username: nobody"
      )
    end

    it "wrong password: 422, 'Incorrect password.' on first failure and counter increments" do
      login!(user, pw: "wrong")
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("Incorrect password.")
      expect(user.reload.auth_attempts).to eq(1)
    end

    it "wrong password reports remaining attempts from the second failure" do
      2.times { login!(user, pw: "wrong") }
      expect(flash[:alert]).to eq(
        "Incorrect password. You have 3 attempts left before your account is locked."
      )
    end

    it "locks the account on the 5th failure and emails an unlock link, but that request 500s" do
      # WART(D-I06): the lockout-triggering (5th) failed login raises (`format.html?` / `sanitize` undefined in the respond_to block) -> 500 instead of the locked message
      perform_enqueued_jobs do
        4.times { login!(user, pw: "wrong") }
        login!(user, pw: "wrong")
      end
      expect(response).to have_http_status(:internal_server_error)
      user.reload
      expect(user.locked).to be(true)
      expect(user.auth_attempts).to eq(5)
      expect(user.locked_until).to be_within(10.seconds).of(5.minutes.from_now)
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([user.email])
      expect(deliveries.first.subject).to eq("Unlock your MakerRepo Account")
    end

    it "the lockout-triggering failure also 500s for json" do
      user.update_columns(auth_attempts: 4)
      post login_authentication_path,
           params: { username_email: user.username, password: "wrong" }, as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(user.reload.locked).to be(true)
    end

    it "locked json response carries the support email" do
      user.update_columns(locked: true, locked_until: 5.minutes.from_now, auth_attempts: 5)
      post login_authentication_path,
           params: { username_email: user.username, password: password }, as: :json
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:unprocessable_content)
      expect(body["support_email"]).to eq("uottawa.makerepo@gmail.com")
      expect(body["error"]).to include("locked")
    end

    it "rejects even the correct password while locked (html: 200 re-render with flash)" do
      user.update_columns(locked: true, locked_until: 5.minutes.from_now, auth_attempts: 5)
      login!(user)
      expect(response).to have_http_status(:ok)
      expect(flash[:alert]).to include("locked due to too many failed login attempts")
      get check_signed_in_path
      expect(JSON.parse(response.body)["signed_in"]).to eq("false")
    end

    it "auto-unlocks after locked_until passes and lets the user in" do
      user.update_columns(locked: true, locked_until: 1.minute.ago, auth_attempts: 5)
      login!(user)
      expect(response).to redirect_to(root_path)
      user.reload
      expect(user.locked).to be(false)
      expect(user.auth_attempts).to eq(0)
    end
  end

  describe "a failed login while already signed in" do
    it "500s: the error re-render swaps @user for a blank User under a signed-in navbar" do
      # WART(D-I25): a failed login POST from a still-signed-in browser re-renders :login with @user = User.new, so the navbar's signed-in links raise (500)
      login!(create(:user, :regular_user))
      post login_authentication_path, params: { username_email: "nobody", password: "x" }
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "unconfirmed / inactive / soft-deleted accounts" do
    it "unconfirmed: re-renders login with a resend link, not signed in" do
      u = create(:user, :regular_user_not_confirmed)
      login!(u)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("resend_email_confirmation")
      get check_signed_in_path
      expect(JSON.parse(response.body)["signed_in"]).to eq("false")
    end

    it "unconfirmed json: 422 'Account not confirmed'" do
      u = create(:user, :regular_user_not_confirmed)
      post login_authentication_path,
           params: { username_email: u.username, password: password }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to eq("Account not confirmed")
    end

    it "inactive (active: false) users can still log in" do
      # WART(D-I03): the `active` flag is never checked at login; inactive accounts sign in normally
      u = create(:user, :regular_user, active: false)
      login!(u)
      expect(response).to redirect_to(root_path)
    end

    it "soft-deleted users cannot log in (default_scope hides them: 'could not find user')" do
      u = create(:user, :regular_user, deleted: true)
      login!(u)
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to start_with("Could not find user")
    end

    it "a session of a user who is soft-deleted afterwards gets a 404 on the next request" do
      login!(user)
      user.update_columns(deleted: true)
      # WART(D-I04): session user is loaded with User.find under the default scope -> RecordNotFound (404 page) for a user soft-deleted mid-session instead of a clean sign-out
      get settings_profile_path
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /check_signed_in" do
    it "guest" do
      get check_signed_in_path
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("signed_in" => "false")
    end

    it "signed in returns user + token" do
      login!(user)
      get check_signed_in_path
      body = JSON.parse(response.body)
      expect(body["signed_in"]).to eq("true")
      expect(body["token"]).to be_present
      expect(body["user"]["id"]).to eq(user.id)
    end

    it "accepts a Bearer JWT instead of a cookie session" do
      get check_signed_in_path, headers: { "Authorization" => "Bearer #{user.token}" }
      expect(JSON.parse(response.body)["signed_in"]).to eq("true")
    end

    it "a JWT survives logout and a password reset (no revocation)" do
      # WART(D-I01): the 14-day JWT returned at login is stateless and is not invalidated by logout or password change; a leaked token stays valid until expiry
      tok = user.token
      login!(user)
      get logout_path
      user.update_columns(password: BCrypt::Password.create("SomethingElse1!x"))
      get check_signed_in_path, headers: { "Authorization" => "Bearer #{tok}" }
      expect(JSON.parse(response.body)["signed_in"]).to eq("true")
    end

    it "rejects an expired JWT" do
      get check_signed_in_path, headers: { "Authorization" => "Bearer #{user.token(1.hour.ago.to_i)}" }
      expect(JSON.parse(response.body)["signed_in"]).to eq("false")
    end

    it "rejects a tampered JWT" do
      get check_signed_in_path, headers: { "Authorization" => "Bearer #{user.token}x" }
      expect(JSON.parse(response.body)["signed_in"]).to eq("false")
    end
  end

  describe "GET /logout" do
    it "clears the session and redirects to root" do
      login!(user)
      get logout_path
      expect(response).to redirect_to(root_path)
      get check_signed_in_path
      expect(JSON.parse(response.body)["signed_in"]).to eq("false")
    end

    it "json" do
      get logout_path, as: :json
      expect(JSON.parse(response.body)).to eq("logout" => "true")
    end

    it "is a GET (CSRF-able logout)" do
      # WART(D-I05): logout is a state-changing GET
      expect(Rails.application.routes.recognize_path("/logout", method: :get)[:action]).to eq("logout")
    end
  end

  describe "session expiry (72h sliding)" do
    it "keeps the session within 72h of the last request" do
      login!(user)
      travel 71.hours do
        get check_signed_in_path
        expect(JSON.parse(response.body)["signed_in"]).to eq("true")
      end
    end

    it "slides: activity refreshes the window" do
      login!(user)
      travel 60.hours do
        get check_signed_in_path
      end
      travel 120.hours do
        get check_signed_in_path
        expect(JSON.parse(response.body)["signed_in"]).to eq("true")
      end
    end

    it "signs out after 72h of inactivity, silently (no flash, no redirect)" do
      login!(user)
      travel 73.hours do
        get check_signed_in_path
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["signed_in"]).to eq("false")
        expect(flash[:alert]).to be_nil
      end
    end

    it "a protected page after expiry redirects to login with back_to and no flash" do
      login!(user)
      travel 73.hours do
        get settings_profile_path
        expect(response).to redirect_to(login_path(back_to: "/settings/profile"))
        expect(flash[:alert]).to be_nil
      end
    end

    it "a JWT session outlives cookie expiry (token valid 14 days)" do
      tok = user.token
      travel 100.hours do
        get check_signed_in_path, headers: { "Authorization" => "Bearer #{tok}" }
        expect(JSON.parse(response.body)["signed_in"]).to eq("true")
      end
    end
  end

  describe "last_seen_at (ApplicationController#set_last_seen_at)" do
    it "is set on the first request after login" do
      login!(user)
      expect(user.reload.last_seen_at).to be_nil
      get settings_profile_path
      expect(user.reload.last_seen_at).to be_within(1.minute).of(Time.current)
    end

    it "is not rewritten within 15 minutes" do
      stamp = 5.minutes.ago.change(usec: 0)
      user.update_columns(last_seen_at: stamp)
      login!(user)
      get settings_profile_path
      expect(user.reload.last_seen_at).to eq(stamp)
    end

    it "is refreshed once older than 15 minutes" do
      user.update_columns(last_seen_at: 20.minutes.ago)
      login!(user)
      get settings_profile_path
      expect(user.reload.last_seen_at).to be > 1.minute.ago
    end
  end

  describe "GET /resend_email_confirmation" do
    it "renders for guests" do
      get resend_email_confirmation_path(email: "a@b.c")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("a@b.c")
    end
  end
end
