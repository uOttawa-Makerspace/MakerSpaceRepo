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

    it "still works with an expired cookie session (session_expiry skipped on create)" do
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

    it "a reset also unlocks a locked account" do
      user.update_columns(locked: true, locked_until: 1.hour.from_now, auth_attempts: 5)
      patch reset_password_confirmation_users_path, params: reset_params(user)
      user.reload
      expect(user.locked).to be(false)
      expect(user.auth_attempts).to eq(0)
      expect(user.locked_until).to be_nil
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

    it "accepts a weak new password (strength validator sees only the bcrypt hash)" do
      # WART(D-I14): reset_password_confirmation (and change_password) bypass the password-strength rule: the validator runs on the already-hashed column, so "abc" is accepted
      patch reset_password_confirmation_users_path, params: reset_params(user, pw: "abc")
      expect(flash[:notice]).to start_with("Your password has been updated")
      expect(user.reload.authenticate_password("abc")).to be(true)
    end

    it "soft-deleted user: the link is treated as expired" do
      u = create(:user, :regular_user)
      p = reset_params(u)
      u.update_columns(deleted: true)
      patch reset_password_confirmation_users_path, params: p
      expect(flash[:alert]).to eq(expired_alert)
    end
  end

  describe "email change (GET /change_email, GET /confirm_edited_email)" do
    let(:new_email) { "brand.new@example.com" }

    it "guest is redirected to login" do
      get change_email_users_path, params: { new_email: new_email, confirm_new_email: new_email }
      expect(response).to redirect_to(login_path(back_to: "/change_email?new_email=brand.new%40example.com&confirm_new_email=brand.new%40example.com"))
    end

    it "sends a confirmation to the NEW address" do
      login!(user)
      get change_email_users_path, params: { new_email: new_email, confirm_new_email: new_email }
      expect(response).to redirect_to(settings_admin_path)
      expect(flash[:notice]).to eq("A confirmation email has been sent to the new email")
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([new_email])
      expect(deliveries.first.subject).to eq("Makerepo | Please confirm your new email")
      expect(user.reload.email).not_to eq(new_email)
    end

    it "mismatch" do
      login!(user)
      get change_email_users_path, params: { new_email: new_email, confirm_new_email: "x@y.z" }
      expect(flash[:alert]).to eq("This confirmation email isn't matching the new email")
      expect(deliveries).to be_empty
    end

    it "already used" do
      login!(user)
      other = create(:user, :regular_user)
      get change_email_users_path, params: { new_email: other.email, confirm_new_email: other.email }
      expect(flash[:alert]).to eq("This email is already used by a MakerRepo Account.")
    end

    it "missing params" do
      login!(user)
      get change_email_users_path
      expect(flash[:alert]).to eq("There was a problem with the email, please try sending the email again.")
    end

    it "confirm_edited_email requires a signed-in session (guest -> login)" do
      get confirm_edited_email_users_path, params: { token: user.generate_email_change_token(new_email) }
      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("http://www.example.com/login?back_to=")
      expect(user.reload.email).not_to eq(new_email)
    end

    it "confirm_edited_email updates the address and notifies the OLD address" do
      old = user.email
      login!(user)
      get confirm_edited_email_users_path, params: { token: user.generate_email_change_token(new_email) }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("The email has been updated to #{new_email} !")
      expect(user.reload.email).to eq(new_email)
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([old])
      expect(deliveries.first.subject).to eq("Makerepo | Email has changed")
    end

    it "works end to end from the emailed link" do
      login!(user)
      get change_email_users_path, params: { new_email: new_email, confirm_new_email: new_email }
      token = CGI.unescape(deliveries.first.body.to_s[/confirm_edited_email\?token=([^"'&\s<]+)/, 1])
      get confirm_edited_email_users_path, params: { token: token }
      expect(user.reload.email).to eq(new_email)
    end

    it "expires after 24 hours" do
      # FIXED(D-I12): email-change tokens are purpose-scoped and expire
      login!(user)
      token = user.generate_email_change_token(new_email)
      travel 25.hours do
        get confirm_edited_email_users_path, params: { token: token }
        expect(flash[:alert]).to eq(expired_alert)
      end
      expect(user.reload.email).not_to eq(new_email)
    end

    it "still works inside 24 hours" do
      login!(user)
      token = user.generate_email_change_token(new_email)
      travel 23.hours do
        get confirm_edited_email_users_path, params: { token: token }
      end
      expect(user.reload.email).to eq(new_email)
    end

    it "cannot be replayed once the address has changed" do
      # FIXED(D-I12): the token is bound to the address it was issued for
      login!(user)
      token = user.generate_email_change_token(new_email)
      get confirm_edited_email_users_path, params: { token: token }
      user.update_columns(email: "changed.again@example.com")
      get confirm_edited_email_users_path, params: { token: token }
      expect(flash[:alert]).to eq(expired_alert)
      expect(user.reload.email).to eq("changed.again@example.com")
    end

    it "is not applied when a different account follows the link, and says so" do
      # FIXED(D-I12): a signed-in bystander can no longer apply a link to the user inside the token
      bystander = create(:user, :regular_user)
      login!(bystander)
      get confirm_edited_email_users_path, params: { token: user.generate_email_change_token(new_email) }
      expect(flash[:alert]).to eq(
        "This link was requested by a different account. Please sign in as the account that requested the change."
      )
      expect(user.reload.email).not_to eq(new_email)
      expect(bystander.reload.email).not_to eq(new_email)
      expect(deliveries).to be_empty
    end

    it "legacy two-token links (user_token + email_token) are refused with the expired message" do
      login!(user)
      get confirm_edited_email_users_path,
          params: { user_token: verifier.generate(user.id),
                    email_token: Rails.application.message_verifier(:email).generate(new_email) }
      expect(flash[:alert]).to eq(expired_alert)
      expect(user.reload.email).not_to eq(new_email)
    end

    it "a token for another purpose does not change the email" do
      login!(user)
      get confirm_edited_email_users_path, params: { token: user.generate_token_for(:password_reset) }
      expect(flash[:alert]).to eq(expired_alert)
    end

    it "confirm_edited_email to an address taken in the meantime fails cleanly: error flash, no mail, no change" do
      # FIXED(D-I13, confirm_edited_email part only): was a 500 on the PG unique index plus a success mail
      other = create(:user, :regular_user)
      original = user.email
      login!(user)
      get confirm_edited_email_users_path, params: { token: user.generate_email_change_token(other.email) }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to start_with("The email could not be updated")
      expect(flash[:notice]).to be_nil
      expect(user.reload.email).to eq(original)
      expect(deliveries).to be_empty
    end

    it "tampered token: generic alert and no change" do
      login!(user)
      get confirm_edited_email_users_path, params: { token: user.generate_email_change_token(new_email) + "x" }
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
