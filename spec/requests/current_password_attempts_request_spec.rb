# frozen_string_literal: true

require "rails_helper"

# change_password and change_email re-authenticate the signed-in user with the
# current password. Guessing it is throttled per signed-in user on Rails.cache
# (UsersController::REAUTH_MAX_FAILURES wrong guesses, shared by both actions;
# an atomic increment under Solid Cache). Only WRONG current passwords count: a
# correct one clears the counter, a blank one and a bad new value do not count.
# The count is read before the password is verified; at the limit the session is
# signed out (a hijacked session is killed, the account is not) and the owner can
# sign in again and carry on. Re-authentication never touches the login lockout
# (auth_attempts, locked): a stranger's failed logins cannot stop the owner from
# changing their password, and changing it clears a timed lockout.
RSpec.describe "Current-password re-authentication", type: :request do
  let(:password) { "asa32A353#" }
  let(:new_password) { "NewPassw0rd!x#9" }
  let!(:user) { create(:user, :regular_user) }
  # The test environment's cache is a null store (no counting); this spec needs real counts.
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  let(:limit_message) { "Too many incorrect current-password attempts. You have been signed out for your security; please sign in again to continue." }

  def log_in!(u = user, pw: password)
    post login_authentication_path, params: { username_email: u.username, password: pw }
    expect(response).to redirect_to(root_path)
  end

  def signed_in?
    get check_signed_in_path
    response.parsed_body["signed_in"] == "true"
  end

  def change_password!(current, valid_new: true)
    patch change_password_user_path(user.username),
          params: { user: { old_password: current, password: new_password,
                            password_confirmation: valid_new ? new_password : "does-not-match" } }
  end

  def change_email!(current, valid_new: true)
    post change_email_users_path,
         params: { new_email: "new.addr@example.com", current_password: current,
                   confirm_new_email: valid_new ? "new.addr@example.com" : "other@example.com" }
  end

  # attempt.(current, valid_new: true); succeeded.() says the change went through.
  shared_examples "a throttled re-authentication" do |attempt, succeeded|
    it "a wrong current password is refused without touching the login lockout" do
      log_in!
      3.times { instance_exec("wrong-password", &attempt) }
      expect(flash[:alert]).to eq("Incorrect current password.")
      expect(user.reload.auth_attempts).to eq(0)
      expect(user.locked).to be(false)
      expect(signed_in?).to be(true)
    end

    it "5 wrong current passwords are allowed; the next submission signs the session out" do
      log_in!
      5.times { instance_exec("wrong-password", &attempt) }
      expect(signed_in?).to be(true)
      instance_exec(password, &attempt) # even the right one: the budget is spent
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq(limit_message)
      expect(signed_in?).to be(false)
      expect(user.reload.locked).to be(false)
      expect(user.authenticate_password(password)).to be(true)
      expect(instance_exec(&succeeded)).to be(false)
    end

    it "after the sign-out the owner signs in again and the CORRECT current password works" do
      log_in!
      6.times { instance_exec("wrong-password", &attempt) }
      expect(signed_in?).to be(false)
      log_in!
      instance_exec(password, &attempt)
      expect(flash[:alert]).to be_nil
      expect(signed_in?).to be(true)
      expect(instance_exec(&succeeded)).to be(true)
    end

    it "a correct current password clears the count" do
      log_in!
      4.times { instance_exec("wrong-password", &attempt) }
      instance_exec(password, &attempt)
      4.times { instance_exec("wrong-password", &attempt) }
      expect(signed_in?).to be(true)
    end

    it "correct current passwords with an unacceptable new value never sign out" do
      log_in!
      8.times { instance_exec(password, valid_new: false, &attempt) }
      expect(signed_in?).to be(true)
      expect(response).not_to redirect_to(login_path)
      instance_exec(password, &attempt)
      expect(instance_exec(&succeeded)).to be(true)
    end

    it "a blank or missing current password is a validation error and does not count" do
      log_in!
      8.times { instance_exec("", &attempt) }
      expect(flash[:alert]).to eq("Please enter your current password.")
      expect(signed_in?).to be(true)
      5.times { instance_exec("wrong-password", &attempt) }
      expect(signed_in?).to be(true) # 5 counted, not 13
    end
  end

  describe "PATCH /:username/change_password" do
    it_behaves_like "a throttled re-authentication", ->(pw, **o) { change_password!(pw, **o) },
                    -> { user.reload.authenticate_password(new_password) }
  end

  describe "POST /change_email" do
    it_behaves_like "a throttled re-authentication", ->(pw, **o) { change_email!(pw, **o) },
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
