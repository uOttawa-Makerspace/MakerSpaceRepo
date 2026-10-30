# frozen_string_literal: true

require "rails_helper"

# change_password and change_email re-authenticate the signed-in user with the
# current password. Guessing it is throttled per signed-in user with Rails'
# rate_limit (UsersController::REAUTH_RATE_LIMIT): 5 attempts per 15 minutes,
# shared by both actions, counted atomically in the database (RateLimitCounter). Going over
# signs the session out: a hijacked session is killed, the account is not.
# A blank current password is a validation error and does not count.
# Re-authentication never touches the login lockout (auth_attempts, locked):
# a stranger's failed logins cannot stop the owner from changing their password,
# and changing it clears a timed lockout.
RSpec.describe "Current-password re-authentication", type: :request do
  let(:password) { "asa32A353#" }
  let(:new_password) { "NewPassw0rd!x#9" }
  let!(:user) { create(:user, :regular_user) }
  let(:limit_message) { "Too many current-password attempts. You have been signed out; please sign in again." }

  def log_in!(u = user, pw: password)
    post login_authentication_path, params: { username_email: u.username, password: pw }
    expect(response).to redirect_to(root_path)
  end

  def signed_in?
    get check_signed_in_path
    response.parsed_body["signed_in"] == "true"
  end

  def change_password!(current)
    patch change_password_user_path(user.username),
          params: { user: { old_password: current, password: new_password, password_confirmation: new_password } }
  end

  def change_email!(current)
    post change_email_users_path,
         params: { new_email: "new.addr@example.com", confirm_new_email: "new.addr@example.com", current_password: current }
  end

  shared_examples "a throttled re-authentication" do |attempt, succeeded|
    it "a wrong current password is refused without touching the login lockout" do
      log_in!
      3.times { instance_exec("wrong-password", &attempt) }
      expect(flash[:alert]).to eq("Incorrect current password.")
      expect(user.reload.auth_attempts).to eq(0)
      expect(user.locked).to be(false)
      expect(signed_in?).to be(true)
    end

    it "the 6th attempt within 15 minutes signs the session out; the account is not locked" do
      log_in!
      5.times { instance_exec("wrong-password", &attempt) }
      expect(signed_in?).to be(true)
      instance_exec(password, &attempt) # even the right one: the budget is spent
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq(limit_message)
      expect(signed_in?).to be(false)
      expect(user.reload.locked).to be(false)
      expect(user.authenticate_password(password)).to be(true)
      expect(user.email).not_to eq("new.addr@example.com")
      log_in! # the owner can sign in again at once
    end

    it "a blank or missing current password is a validation error and does not count" do
      log_in!
      8.times { instance_exec("", &attempt) }
      expect(flash[:alert]).to eq("Please enter your current password.")
      expect(signed_in?).to be(true)
      instance_exec(password, &attempt)
      expect(instance_exec(&succeeded)).to be(true)
    end
  end

  describe "PATCH /:username/change_password" do
    it_behaves_like "a throttled re-authentication", ->(pw) { change_password!(pw) },
                    -> { user.reload.authenticate_password(new_password) }
  end

  describe "POST /change_email" do
    it_behaves_like "a throttled re-authentication", ->(pw) { change_email!(pw) },
                    -> { ActionMailer::Base.deliveries.any? { |m| m.to == ["new.addr@example.com"] } }
  end

  it "the two actions share one budget per user" do
    log_in!
    3.times { change_password!("wrong-password") }
    2.times { change_email!("wrong-password") }
    change_email!("wrong-password")
    expect(flash[:alert]).to eq(limit_message)
    expect(signed_in?).to be(false)
  end

  it "the budget is per user: another user's attempts do not count" do
    other = create(:user, :regular_user)
    log_in!(other)
    5.times do
      post change_email_users_path,
           params: { new_email: "x@example.com", confirm_new_email: "x@example.com", current_password: "wrong" }
    end
    reset!
    log_in!
    change_password!(password)
    expect(response).to redirect_to(settings_admin_path)
    expect(user.reload.authenticate_password(new_password)).to be(true)
  end

  describe "while the account is locked by a stranger's failed logins" do
    before do
      log_in!
      User::MAX_AUTH_ATTEMPTS.times do
        post login_authentication_path, params: { username_email: user.username, password: "nope" }
      end
      expect(user.reload.lock_in_effect?).to be(true)
    end

    it "the signed-in owner can still change the password, which clears the timed lockout" do
      change_password!(password)
      expect(response).to redirect_to(settings_admin_path)
      user.reload
      expect(user.authenticate_password(new_password)).to be(true)
      expect(user.locked).to be(false)
      expect(user.auth_attempts).to eq(0)
    end

    it "the signed-in owner can still request an email change" do
      change_email!(password)
      expect(flash[:notice]).to eq("A confirmation email has been sent to the new email")
    end
  end
end
