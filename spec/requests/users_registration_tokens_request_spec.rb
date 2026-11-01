# frozen_string_literal: true

require "rails_helper"

# Characterization spec for registration, email confirmation, password reset,
# email change and account-unlock tokens (UsersController, StaticPages
# forgot/reset, MsrMailer user emails). Chunk 9 "Identity".
#
# Tokens are ActiveSupport::MessageVerifier messages (`:user`, `:email`,
# `'unlock'`) with NO purpose and NO expiry baked in (except the reset flow's
# separately signed expiry timestamp). Emails are pinned by delivered outcome.
# Turnstile verification short-circuits to true in the test env
# (`TurnstileHelper#verify_turnstile`), so there is no captcha HTTP call.

RSpec.describe "User registration and tokens (HTTP contract)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "asa32A353#" }
  let(:user) { create(:user, :regular_user) }
  let(:verifier) { Rails.application.message_verifier(:user) }

  before { block_external_http! }

  def deliveries
    ActionMailer::Base.deliveries
  end

  def login!(u, pw: password)
    post login_authentication_path, params: { username_email: u.username, password: pw }
  end

  def signed_in?
    get check_signed_in_path
    JSON.parse(response.body)["signed_in"] == "true"
  end

  def reset_params(u, pw: "NewPassw0rd!x#9", confirm: pw)
    {
      token: u.generate_token_for(:password_reset),
      password: pw,
      password_confirmation: confirm
    }
  end

  let(:expired_alert) { "This link has expired or has already been used. Please request a new one." }

  def registration_params(overrides = {})
    FactoryBot.attributes_for(:user, :regular_user, password: password).merge(overrides)
  end

  describe "POST /new (registration)" do
    it "creates an unconfirmed user, emails a confirmation link, redirects with notice" do
      attrs = registration_params
      expect { post users_path, params: { user: attrs } }.to change(User, :count).by(1)
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq(
        "Account has been created, please look in your emails to confirm your email address."
      )
      created = User.find_by(username: attrs[:username])
      expect(created.confirmed).to be(false)
      expect(created.role).to eq("regular_user")
      expect(BCrypt::Password.new(created.password)).to eq(password)
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([created.email])
      expect(deliveries.first.subject).to eq("Makerepo | Please confirm your email")
      expect(deliveries.first.body.to_s).to include("/confirm?token=")
    end

    it "json: success is answered with status 422 (!) and a plain string" do
      # WART(D-I07): JSON registration success responds 422 unprocessable_content
      post users_path, params: { user: registration_params }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to eq(
        "Account has been created, please look in your emails to confirm your email address."
      )
    end

    it "invalid: re-renders new with 422 and persists nothing, sends no mail" do
      expect {
        post users_path, params: { user: registration_params(username: "bad name!") }
      }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(deliveries).to be_empty
    end

    it "invalid json: returns the errors hash" do
      post users_path, params: { user: registration_params(email: "") }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to have_key("email")
    end

    it "rejects a weak password" do
      expect {
        post users_path, params: { user: registration_params(password: "abc") }
      }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "checks a bcrypt-shaped plaintext password for strength like any other (it is not skipped by its shape)" do
      shaped = "$2a$10$" + ("a" * 22) + "signupname" + ("b" * 21)
      expect {
        post users_path, params: { user: registration_params(username: "signupname", password: shaped) }
      }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a duplicate email regardless of case" do
      existing = create(:user, :regular_user)
      expect {
        post users_path, params: { user: registration_params(email: existing.email.upcase) }
      }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires the waiver" do
      expect {
        post users_path, params: { user: registration_params(read_and_accepted_waiver_form: false) }
      }.not_to change(User, :count)
    end

    it "ignores a mass-assigned role (not permitted)" do
      attrs = registration_params.merge(role: "admin", confirmed: true)
      post users_path, params: { user: attrs }
      created = User.find_by(username: attrs[:username])
      expect(created.role).to eq("regular_user")
      expect(created.confirmed).to be(false)
    end

    it "stores a valid avatar" do
      attrs = registration_params.merge(avatar: AvatarTestHelper.png)
      post users_path, params: { user: attrs }
      expect(User.find_by(username: attrs[:username]).avatar).to be_attached
    end

    it "rejects a non-image avatar" do
      attrs = registration_params.merge(avatar: AvatarTestHelper.stl)
      expect { post users_path, params: { user: attrs } }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "works for a signed-in user too (no guest check on create)" do
      # WART(D-I08): UsersController#create has no signed-in guard, unlike #new which redirects
      login!(user)
      expect { post users_path, params: { user: registration_params } }.to change(User, :count).by(1)
      expect(response).to redirect_to(root_path)
    end

    it "works for a guest (no session)" do
      post users_path, params: { user: registration_params }
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /new" do
    it "renders for guests" do
      get new_user_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects signed-in users" do
      login!(user)
      get new_user_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /resend_confirmation" do
    it "emails a fresh confirmation link to a known address" do
      u = create(:user, :regular_user_not_confirmed)
      get resend_confirmation_users_path, params: { user: { email: u.email } }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("A new confirmation email has been sent")
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([u.email])
      expect(deliveries.first.subject).to eq("Makerepo | Please confirm your email")
    end

    it "tells the caller whether an email is registered (account enumeration)" do
      # WART(D-I09): resend_confirmation reveals whether an email has an account, unlike reset_password which is uniform
      get resend_confirmation_users_path, params: { user: { email: "nobody@example.com" } }
      expect(flash[:alert]).to eq("No users with that email were found. Please select a valid email.")
      expect(deliveries).to be_empty
    end

    it "redirects back to the referer when present" do
      get resend_confirmation_users_path,
          params: { user: { email: "nobody@example.com" } },
          headers: { "HTTP_REFERER" => "http://www.example.com/login" }
      expect(response).to redirect_to("http://www.example.com/login")
    end

    it "does not send for soft-deleted users" do
      u = create(:user, :regular_user_not_confirmed, deleted: true)
      get resend_confirmation_users_path, params: { user: { email: u.email } }
      expect(flash[:alert]).to start_with("No users with that email")
    end

    it "without the user param 500s (nil[:email])" do
      # WART(D-I28): resend_confirmation reads params[:user][:email] unguarded, so a missing user param is a 500 instead of the ParameterMissing redirect
      get resend_confirmation_users_path
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "GET /confirm" do
    let(:unconfirmed) { create(:user, :regular_user_not_confirmed) }
    let(:confirm_token) { unconfirmed.generate_token_for(:email_confirmation) }

    it "confirms the account and sends the welcome email" do
      get confirm_users_path, params: { token: confirm_token }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq(
        "The email has been confirmed, you can now fully use your Makerepo Account !"
      )
      expect(unconfirmed.reload.confirmed).to be(true)
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([unconfirmed.email])
      expect(deliveries.first.subject).to eq("Welcome to MakerRepo")
    end

    it "the token expires after 3 days" do
      # FIXED(D-I11): confirmation tokens are purpose-scoped and expire (3 days)
      token = confirm_token
      travel 73.hours do
        get confirm_users_path, params: { token: token }
        expect(flash[:alert]).to eq(expired_alert)
        expect(unconfirmed.reload.confirmed).to be(false)
      end
    end

    it "still works just inside 3 days" do
      token = confirm_token
      travel 71.hours do
        get confirm_users_path, params: { token: token }
        expect(unconfirmed.reload.confirmed).to be(true)
      end
    end

    it "cannot be replayed: the second use is refused and sends no second welcome email" do
      # FIXED(D-I11): the token is bound to the confirmed flag
      token = confirm_token
      2.times { get confirm_users_path, params: { token: token } }
      expect(deliveries.map(&:subject)).to eq(["Welcome to MakerRepo"])
      expect(flash[:alert]).to eq(expired_alert)
    end

    it "a legacy token (plain :user verifier message, mailed before the deploy) is refused with the expired message" do
      get confirm_users_path, params: { token: verifier.generate(unconfirmed.id) }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(expired_alert)
      expect(unconfirmed.reload.confirmed).to be(false)
      expect(deliveries).to be_empty
    end

    it "tampered token: alert, nothing changes" do
      get confirm_users_path, params: { token: confirm_token + "x" }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(expired_alert)
      expect(unconfirmed.reload.confirmed).to be(false)
      expect(deliveries).to be_empty
    end

    it "missing token: same alert" do
      get confirm_users_path
      expect(flash[:alert]).to eq(expired_alert)
    end

    it "another purpose's token (password reset) does not confirm" do
      get confirm_users_path, params: { token: unconfirmed.generate_token_for(:password_reset) }
      expect(flash[:alert]).to eq(expired_alert)
      expect(unconfirmed.reload.confirmed).to be(false)
    end

    it "a soft-deleted user's token is refused" do
      u = create(:user, :regular_user_not_confirmed)
      tok = u.generate_token_for(:email_confirmation)
      u.update_columns(deleted: true)
      get confirm_users_path, params: { token: tok }
      expect(flash[:alert]).to eq(expired_alert)
      expect(User.unscoped.find(u.id).confirmed).to be(false)
    end

    it "the emailed link from registration confirms the account" do
      attrs = registration_params
      post users_path, params: { user: attrs }
      token = CGI.unescape(deliveries.first.body.to_s[/confirm\?token=([^"'&\s<]+)/, 1])
      get confirm_users_path, params: { token: token }
      expect(User.find_by(username: attrs[:username]).confirmed).to be(true)
    end
  end

  describe "password reset request (StaticPages#reset_password)" do
    it "GET /forgot_password renders" do
      get forgot_password_path
      expect(response).to have_http_status(:ok)
    end

    it "emails a reset link to a known address and answers uniformly" do
      patch reset_password_path, params: { email: " #{user.email.upcase} " }
      expect(response).to have_http_status(:ok)
      expect(flash[:notice]).to eq("A reset link email has been sent to the email if the account exists.")
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([user.email])
      expect(deliveries.first.subject).to eq("Reset your MakerRepo password")
      expect(deliveries.first.body.to_s).to include("reset_password_form?token=")
    end

    it "unknown address: same notice, no mail" do
      patch reset_password_path, params: { email: "nobody@example.com" }
      expect(flash[:notice]).to eq("A reset link email has been sent to the email if the account exists.")
      expect(deliveries).to be_empty
    end

    it "blank address: alert, no mail" do
      patch reset_password_path, params: { email: "" }
      expect(response).to have_http_status(:ok)
      expect(flash.now[:alert]).to eq("Please enter an email address.")
      expect(deliveries).to be_empty
    end

    it "soft-deleted user gets no email" do
      u = create(:user, :regular_user, deleted: true)
      patch reset_password_path, params: { email: u.email }
      expect(deliveries).to be_empty
    end

    it "sends to locked and inactive accounts too" do
      u = create(:user, :regular_user, active: false, locked: true)
      patch reset_password_path, params: { email: u.email }
      expect(deliveries.size).to eq(1)
    end
  end

  describe "password reset (GET /reset_password_form, PATCH /reset_password_confirmation)" do
    it "renders the form with the token as a hidden field" do
      token = user.generate_token_for(:password_reset)
      get reset_password_form_users_path, params: { token: token }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="token"').and include(token)
    end

    it "a garbage, missing or legacy-format link redirects to the forgot-password page with the expired message" do
      # FIXED(D-I11): the form validates the token on GET; previously mailed links (user_token + expiry_date_token) are dead
      [{ token: "garbage" }, {}, { user_token: verifier.generate(user.id), expiry_date_token: verifier.generate(1.day.from_now) }].each do |params|
        get reset_password_form_users_path, params: params
        expect(response).to redirect_to(forgot_password_path)
        expect(flash[:alert]).to eq(expired_alert)
      end
    end

    it "full flow: emailed link resets the password, confirms by email, and the new password works" do
      patch reset_password_path, params: { email: user.email }
      link = deliveries.first.body.to_s[/reset_password_form\?[^"'\s<]+/]
      query = Rack::Utils.parse_query(CGI.unescapeHTML(link.split("?", 2).last))
      deliveries.clear

      patch reset_password_confirmation_users_path,
            params: { token: query["token"],
                      password: "NewPassw0rd!x#9", password_confirmation: "NewPassw0rd!x#9" }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Your password has been updated, an email will be sent to confirm!")
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([user.email])
      expect(deliveries.first.subject).to eq("MakerRepo | Your password has been changed")

      login!(user, pw: "NewPassw0rd!x#9")
      expect(response).to redirect_to(root_path)
    end

    it "the old password stops working" do
      patch reset_password_confirmation_users_path, params: reset_params(user)
      login!(user)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "mismatched confirmation: alert, password unchanged" do
      patch reset_password_confirmation_users_path,
            params: reset_params(user, confirm: "different")
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Your password and password confirmation do not match.")
      expect(user.reload.authenticate_password(password)).to be(true)
    end

    it "a link older than 2 hours is expired: alert, password unchanged" do
      # FIXED(D-I11): reset tokens expire after 2 hours (was a separate 24h timestamp)
      params = reset_params(user)
      travel 121.minutes do
        patch reset_password_confirmation_users_path, params: params
        expect(flash[:alert]).to eq(expired_alert)
      end
      expect(user.reload.authenticate_password(password)).to be(true)
    end

    it "a link younger than 2 hours still works" do
      params = reset_params(user)
      travel 119.minutes do
        patch reset_password_confirmation_users_path, params: params
        expect(flash[:notice]).to start_with("Your password has been updated")
      end
    end

    it "tampered token: expired alert, password unchanged" do
      p = reset_params(user)
      patch reset_password_confirmation_users_path, params: p.merge(token: p[:token] + "x")
      expect(flash[:alert]).to eq(expired_alert)
      expect(user.reload.authenticate_password(password)).to be(true)
    end

    it "the same link cannot be reused after a successful reset" do
      # FIXED(D-I10): the token is bound to the password digest, so it dies once the password changes
      p = reset_params(user)
      patch reset_password_confirmation_users_path, params: p
      expect(flash[:notice]).to start_with("Your password has been updated")
      patch reset_password_confirmation_users_path,
            params: p.merge(password: "SecondPassw0rd!x#7", password_confirmation: "SecondPassw0rd!x#7")
      expect(flash[:alert]).to eq(expired_alert)
      expect(user.reload.authenticate_password("NewPassw0rd!x#9")).to be(true)
    end

    it "a mismatched confirmation does not consume the link" do
      p = reset_params(user)
      patch reset_password_confirmation_users_path, params: p.merge(password_confirmation: "different")
      patch reset_password_confirmation_users_path, params: p
      expect(flash[:notice]).to start_with("Your password has been updated")
    end

    it "an old confirmation-email token (same :user verifier, no purpose) cannot reset a password" do
      # FIXED(D-I11): reset tokens are purpose-scoped and bound to the user; a confirmation token plus any timestamp no longer works
      patch reset_password_confirmation_users_path,
            params: { token: verifier.generate(user.id), user_token: verifier.generate(user.id),
                      expiry_date_token: verifier.generate(1.day.from_now),
                      password: "NewPassw0rd!x#9", password_confirmation: "NewPassw0rd!x#9" }
      expect(flash[:alert]).to eq(expired_alert)
      expect(user.reload.authenticate_password(password)).to be(true)
    end

    it "another user's reset token cannot reset this account" do
      other = create(:user, :regular_user)
      patch reset_password_confirmation_users_path, params: reset_params(other)
      expect(user.reload.authenticate_password(password)).to be(true)
      expect(other.reload.authenticate_password(password)).to be(false)
    end

    it "a reset revokes JWTs issued before it (D-I01)" do
      tok = user.token
      patch reset_password_confirmation_users_path, params: reset_params(user)
      get check_signed_in_path, headers: { "Authorization" => "Bearer #{tok}" }
      expect(JSON.parse(response.body)["signed_in"]).to eq("false")
    end

    it "a reset also clears a timed (brute-force) lockout, current or lapsed" do
      [4.minutes.from_now, 1.minute.ago].each do |until_time|
        user.update_columns(locked: true, locked_until: until_time, auth_attempts: 5)
        patch reset_password_confirmation_users_path, params: reset_params(user)
        user.reload
        expect(user.locked).to be(false)
        expect(user.auth_attempts).to eq(0)
        expect(user.locked_until).to be_nil
      end
    end

    it "works for a legacy user whose row fails an unrelated validation" do
      # FIXED: only the password columns are written
      user.update_columns(username: "old_user_name_longer_than_20", gender: "stale value")
      expect(user.reload).not_to be_valid
      patch reset_password_confirmation_users_path, params: reset_params(user)
      expect(flash[:notice]).to start_with("Your password has been updated")
      expect(user.reload.authenticate_password("NewPassw0rd!x#9")).to be(true)
      expect(user.token_version).to eq(1)
    end

    it "a database error while storing the password is reported, shown as a failed change, and sends no mail" do
      allow_any_instance_of(User).to receive(:bump_token_version!).and_raise(ActiveRecord::StatementInvalid, "boom")
      expect(Rails.error).to receive(:report).with(an_instance_of(ActiveRecord::StatementInvalid), handled: true)
      patch reset_password_confirmation_users_path, params: reset_params(user)
      expect(flash[:alert]).to start_with("An error occured while trying to change your password")
      expect(deliveries).to be_empty
    end

    it "a concurrent bump during the reset is an expected race: not reported, told to use the link again, link stays valid" do
      allow_any_instance_of(User).to receive(:store_new_password!).and_wrap_original do |m, *args, **opts|
        User.where(id: m.receiver.id).update_all("token_version = token_version + 1")
        m.call(*args, **opts)
      end
      expect(Rails.error).not_to receive(:report)
      params = reset_params(user)
      patch reset_password_confirmation_users_path, params: params
      expect(response).to redirect_to(reset_password_form_users_path(token: params[:token]))
      expect(flash[:alert]).to eq("Your account changed while resetting the password. Please use the link again.")
      expect(deliveries).to be_empty
      allow_any_instance_of(User).to receive(:store_new_password!).and_call_original
      patch reset_password_confirmation_users_path, params: params
      expect(flash[:notice]).to start_with("Your password has been updated")
    end

    it "a double submit gets the neutral invalid-link message (the link no longer resolves), not 'use the link again'" do
      params = reset_params(user)
      allow_any_instance_of(User).to receive(:store_new_password!).and_wrap_original do |m, *args, **opts|
        # the first submit commits between this request's token lookup and its write
        User.where(id: m.receiver.id).update_all(
          ["password = ?, token_version = token_version + 1", BCrypt::Password.create("Other-passw0rd#y", cost: 4).to_s]
        )
        m.call(*args, **opts)
      end
      patch reset_password_confirmation_users_path, params: params
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq("Your reset link is no longer valid. Please sign in or request a new link.")
      expect(deliveries).to be_empty
    end

    it "a link that stops resolving because the account was soft-deleted gets the same neutral message (no account state revealed)" do
      params = reset_params(user)
      allow_any_instance_of(User).to receive(:store_new_password!).and_wrap_original do |m, *args, **opts|
        User.unscoped.where(id: m.receiver.id).update_all("deleted = true, token_version = token_version + 1")
        m.call(*args, **opts)
      end
      patch reset_password_confirmation_users_path, params: params
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq("Your reset link is no longer valid. Please sign in or request a new link.")
    end

    it "a reset does not lift an admin lock: the new password is saved and the login is still refused" do
      # FIXED: only the timed brute-force lockout is cleared by a reset
      user.update_columns(locked: true, locked_until: 99.years.from_now, auth_attempts: 5)
      patch reset_password_confirmation_users_path, params: reset_params(user)
      expect(flash[:notice]).to start_with("Your password has been updated")
      user.reload
      expect(user.authenticate_password("NewPassw0rd!x#9")).to be(true)
      expect(user.locked).to be(true)
      expect(user.locked_until).to be > 90.years.from_now
      post login_authentication_path, params: { username_email: user.username, password: "NewPassw0rd!x#9" }
      expect(flash[:alert]).to include("locked")
      user.update_columns(locked_until: nil)
      patch reset_password_confirmation_users_path, params: reset_params(user, pw: "AnotherPassw0rd!y#7")
      expect(user.reload.locked).to be(true)
    end

    it "a reset does not confirm an unconfirmed account" do
      u = create(:user, :regular_user_not_confirmed)
      patch reset_password_confirmation_users_path, params: reset_params(u)
      expect(u.reload.confirmed).to be(false)
    end

    it "does not sign the user in" do
      patch reset_password_confirmation_users_path, params: reset_params(user)
      expect(signed_in?).to be(false)
    end

    it "refuses a weak new password and leaves the link usable" do
      # FIXED(D-I14, reset action): the strength rules run on the plain password
      p = reset_params(user, pw: "abc")
      patch reset_password_confirmation_users_path, params: p
      expect(response).to redirect_to(reset_password_form_users_path(token: p[:token]))
      expect(flash[:alert]).to start_with("Your password was not changed:")
      expect(user.reload.authenticate_password(password)).to be(true)
      patch reset_password_confirmation_users_path, params: reset_params(user)
      expect(flash[:notice]).to start_with("Your password has been updated")
    end

    it "succeeds even when the bcrypt hash happens to contain the username (strength rules are not re-run on the hash)" do
      # FIXED: the hashing save re-ran the nobspw validator on the hash and raised (save!) for such a hash
      u = create(:user, :regular_user, username: "hunterxsmith")
      forced = "$2a$12$" + ("a" * 22) + "hunterxsmith" + ("b" * 19)
      allow(BCrypt::Password).to receive(:create).and_return(BCrypt::Password.new(forced))
      patch reset_password_confirmation_users_path, params: reset_params(u)
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to start_with("Your password has been updated")
      expect(u.reload.password).to eq(forced)
    end

    it "soft-deleted user: the link is treated as expired" do
      u = create(:user, :regular_user)
      p = reset_params(u)
      u.update_columns(deleted: true)
      patch reset_password_confirmation_users_path, params: p
      expect(flash[:alert]).to eq(expired_alert)
    end
  end

  # INF-02: both halves of the email change used to be GETs (no password,
  # applied on a link click), so a cross-site navigation could mail a token for
  # the victim's account to an attacker's address and then apply it. Now:
  # POST /change_email needs the current password; the emailed link only shows a
  # confirmation page (GET) that does nothing until the signed-in owner of the
  # token submits it (POST); the token dies once the address changes.
  describe "email change (POST /change_email, GET+POST /confirm_edited_email)" do
    let(:new_email) { "brand.new@example.com" }
    let(:change_params) { { new_email: new_email, confirm_new_email: new_email, current_password: password } }

    def confirm_form_token
      Nokogiri::HTML(response.body).at_css("form[action='/confirm_edited_email'] input[name='token']")&.[]("value")
    end

    it "a cross-site GET to /change_email does nothing: no token is mailed (it falls through to the profile catch-all, a 404)" do
      login!(user)
      get "/change_email", params: { new_email: new_email, confirm_new_email: new_email }
      expect(response).to have_http_status(:not_found)
      expect(deliveries).to be_empty
      expect(user.reload.email).not_to eq(new_email)
    end

    it "guest is redirected to login" do
      post change_email_users_path, params: change_params
      expect(response.location).to start_with("http://www.example.com/login")
      expect(deliveries).to be_empty
    end

    it "sends a confirmation to the NEW address when the current password is right" do
      login!(user)
      post change_email_users_path, params: change_params
      expect(response).to redirect_to(settings_admin_path)
      expect(flash[:notice]).to eq("A confirmation email has been sent to the new email")
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([new_email])
      expect(deliveries.first.subject).to eq("Makerepo | Please confirm your new email")
      expect(user.reload.email).not_to eq(new_email)
    end

    it "is refused without the current password" do
      login!(user)
      post change_email_users_path, params: change_params.except(:current_password)
      expect(response).to redirect_to(settings_admin_path)
      expect(flash[:alert]).to eq("Please enter your current password.")
      expect(deliveries).to be_empty
    end

    it "is refused with a wrong current password" do
      login!(user)
      post change_email_users_path, params: change_params.merge(current_password: "Wrong-passw0rd#")
      expect(response).to redirect_to(settings_admin_path)
      expect(flash[:alert]).to eq("Incorrect current password.")
      expect(deliveries).to be_empty
    end

    it "mismatch" do
      login!(user)
      post change_email_users_path, params: change_params.merge(confirm_new_email: "x@y.z")
      expect(flash[:alert]).to eq("This confirmation email isn't matching the new email")
      expect(deliveries).to be_empty
    end

    it "already used" do
      login!(user)
      other = create(:user, :regular_user)
      post change_email_users_path, params: change_params.merge(new_email: other.email, confirm_new_email: other.email)
      expect(flash[:alert]).to eq("This email is already used by a MakerRepo Account.")
      expect(deliveries).to be_empty
    end

    it "missing addresses" do
      login!(user)
      post change_email_users_path, params: { current_password: password }
      expect(flash[:alert]).to eq("There was a problem with the email, please try sending the email again.")
    end

    it "the confirmation link requires a signed-in session (guest -> login)" do
      get confirm_edited_email_users_path, params: { token: user.generate_email_change_token(new_email) }
      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("http://www.example.com/login?back_to=")
      expect(user.reload.email).not_to eq(new_email)
    end

    it "GET on the confirmation link only shows a confirmation page: nothing is applied or mailed" do
      login!(user)
      token = user.generate_email_change_token(new_email)
      get confirm_edited_email_users_path, params: { token: token }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(new_email))
      expect(confirm_form_token).to eq(token)
      expect(Nokogiri::HTML(response.body).at_css("form[action='/confirm_edited_email']")["method"]).to eq("post")
      expect(user.reload.email).not_to eq(new_email)
      expect(deliveries).to be_empty
    end

    it "POST applies the change and notifies the OLD address" do
      old = user.email
      login!(user)
      post confirm_edited_email_users_path, params: { token: user.generate_email_change_token(new_email) }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("The email has been updated to #{new_email} !")
      expect(user.reload.email).to eq(new_email)
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([old])
      expect(deliveries.first.subject).to eq("Makerepo | Email has changed")
    end

    it "works end to end from the emailed link" do
      login!(user)
      post change_email_users_path, params: change_params
      token = CGI.unescape(deliveries.first.body.to_s[/confirm_edited_email\?token=([^"'&\s<]+)/, 1])
      get confirm_edited_email_users_path, params: { token: token }
      post confirm_edited_email_users_path, params: { token: confirm_form_token }
      expect(user.reload.email).to eq(new_email)
    end

    it "is single-use: the same token is refused once the address has changed" do
      login!(user)
      token = user.generate_email_change_token(new_email)
      post confirm_edited_email_users_path, params: { token: token }
      expect(user.reload.email).to eq(new_email)
      deliveries.clear
      user.update_columns(email: "changed.again@example.com")
      post confirm_edited_email_users_path, params: { token: token }
      expect(flash[:alert]).to eq(expired_alert)
      expect(user.reload.email).to eq("changed.again@example.com")
      expect(deliveries).to be_empty
    end

    it "dies with a password change (the token is bound to the account's token_version)" do
      token = user.generate_email_change_token(new_email)
      user.store_new_password!("An0ther-passw0rd#x")
      login!(user, pw: "An0ther-passw0rd#x")
      post confirm_edited_email_users_path, params: { token: token }
      expect(flash[:alert]).to eq(expired_alert)
      expect(user.reload.email).not_to eq(new_email)
    end

    it "expires after 24 hours" do
      login!(user)
      token = user.generate_email_change_token(new_email)
      travel 25.hours do
        login!(user)
        post confirm_edited_email_users_path, params: { token: token }
        expect(flash[:alert]).to eq(expired_alert)
      end
      expect(user.reload.email).not_to eq(new_email)
    end

    it "still works inside 24 hours" do
      login!(user)
      token = user.generate_email_change_token(new_email)
      travel 23.hours do
        post confirm_edited_email_users_path, params: { token: token }
      end
      expect(user.reload.email).to eq(new_email)
    end

    it "a POST from a different signed-in account is refused, and says so" do
      bystander = create(:user, :regular_user)
      login!(bystander)
      post confirm_edited_email_users_path, params: { token: user.generate_email_change_token(new_email) }
      expect(flash[:alert]).to eq(
        "This link was requested by a different account. Please sign in as the account that requested the change."
      )
      expect(user.reload.email).not_to eq(new_email)
      expect(bystander.reload.email).not_to eq(new_email)
      expect(deliveries).to be_empty
    end

    it "the confirmation page for a different signed-in account offers nothing to submit" do
      bystander = create(:user, :regular_user)
      login!(bystander)
      get confirm_edited_email_users_path, params: { token: user.generate_email_change_token(new_email) }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to start_with("This link was requested by a different account.")
    end

    it "legacy two-token links (user_token + email_token) are refused with the expired message" do
      login!(user)
      post confirm_edited_email_users_path,
           params: { user_token: verifier.generate(user.id),
                     email_token: Rails.application.message_verifier(:email).generate(new_email) }
      expect(flash[:alert]).to eq(expired_alert)
      expect(user.reload.email).not_to eq(new_email)
    end

    it "a token for another purpose does not change the email" do
      login!(user)
      post confirm_edited_email_users_path, params: { token: user.generate_token_for(:password_reset) }
      expect(flash[:alert]).to eq(expired_alert)
    end

    it "to an address taken in the meantime fails cleanly: error flash, no mail, no change" do
      other = create(:user, :regular_user)
      original = user.email
      login!(user)
      post confirm_edited_email_users_path, params: { token: user.generate_email_change_token(other.email) }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to start_with("The email could not be updated")
      expect(flash[:notice]).to be_nil
      expect(user.reload.email).to eq(original)
      expect(deliveries).to be_empty
    end

    it "tampered token: generic alert and no change" do
      login!(user)
      post confirm_edited_email_users_path, params: { token: user.generate_email_change_token(new_email) + "x" }
      expect(flash[:alert]).to eq(expired_alert)
      expect(user.reload.email).not_to eq(new_email)
    end
  end

  describe "GET /unlock_account" do
    let(:locked_user) do
      create(:user, :regular_user, locked: true, locked_until: 1.hour.from_now, auth_attempts: 5)
    end
    let(:unlock_token) { locked_user.generate_token_for(:account_unlock) }

    it "unlocks the account and clears counters" do
      get unlock_account_users_path, params: { token: unlock_token }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("The account has been unlocked!")
      locked_user.reload
      expect(locked_user.locked).to be(false)
      expect(locked_user.auth_attempts).to eq(0)
      expect(locked_user.locked_until).to be_nil
    end

    it "is single-use: the link is refused once the account is unlocked" do
      # FIXED(D-I11): was silent on an already-unlocked account; the token is bound to the lock
      token = unlock_token
      get unlock_account_users_path, params: { token: token }
      get unlock_account_users_path, params: { token: token }
      expect(flash[:alert]).to eq(expired_alert)
    end

    it "expires after 1 hour" do
      # FIXED(D-I11)
      token = unlock_token
      travel 61.minutes do
        get unlock_account_users_path, params: { token: token }
      end
      expect(flash[:alert]).to eq(expired_alert)
      expect(locked_user.reload.locked).to be(true)
    end

    it "unlocks a legacy-invalid account too (the unlock is written without validations)" do
      locked_user.update_columns(gender: "stale value")
      get unlock_account_users_path, params: { token: unlock_token }
      expect(flash[:notice]).to eq("The account has been unlocked!")
      expect(locked_user.reload.locked).to be(false)
      expect(locked_user.auth_attempts).to eq(0)
    end

    it "invalid token" do
      get unlock_account_users_path, params: { token: "nope" }
      expect(flash[:alert]).to eq(expired_alert)
    end

    it "a legacy 'unlock' verifier token is refused with the expired message" do
      get unlock_account_users_path, params: { token: Rails.application.message_verifier("unlock").generate(locked_user.id) }
      expect(flash[:alert]).to eq(expired_alert)
      expect(locked_user.reload.locked).to be(true)
    end

    it "a confirmation token does not unlock" do
      get unlock_account_users_path, params: { token: locked_user.generate_token_for(:email_confirmation) }
      expect(flash[:alert]).to eq(expired_alert)
      expect(locked_user.reload.locked).to be(true)
    end

    it "works end to end from the emailed lockout link" do
      u = create(:user, :regular_user)
      u.lock_account!
      expect(deliveries.size).to eq(1)
      token = deliveries.first.body.to_s[/token=([^"'&\s<]+)/, 1]
      get unlock_account_users_path, params: { token: CGI.unescape(token) }
      expect(u.reload.locked).to be(false)
    end
  end
end
