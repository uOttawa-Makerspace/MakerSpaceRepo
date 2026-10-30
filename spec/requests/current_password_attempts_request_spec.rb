# frozen_string_literal: true

require "rails_helper"

# change_password and change_email ask for the current password. With a
# hijacked session that check could be guessed without limit. It now goes
# through the login's bookkeeping (CredentialAuthenticator.verify_current_password):
# each wrong password counts towards User::MAX_AUTH_ATTEMPTS on the same
# auth_attempts counter as a login, the account locks the same way (timed
# lockout plus the unlock email), and while the lock is in effect even the right
# password is refused.
RSpec.describe "Current-password checks count like login attempts", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "asa32A353#" }
  let(:new_password) { "NewPassw0rd!x#9" }
  let!(:user) { create(:user, :regular_user) }

  def log_in!
    post login_authentication_path, params: { username_email: user.username, password: password }
    expect(response).to redirect_to(root_path)
  end

  def change_password!(old)
    patch change_password_user_path(user.username),
          params: { user: { old_password: old, password: new_password, password_confirmation: new_password } }
  end

  def change_email!(current)
    post change_email_users_path,
         params: { new_email: "new.addr@example.com", confirm_new_email: "new.addr@example.com", current_password: current }
  end

  def unlock_mails
    ActionMailer::Base.deliveries.select { |m| m.to == [user.email] && m.subject.to_s.downcase.include?("unlock") }
  end

  shared_examples "a counted current-password check" do |attempt|
    it "counts each wrong password on the login counter" do
      log_in!
      3.times { instance_exec("wrong-#{rand(1000)}", &attempt) }
      expect(user.reload.auth_attempts).to eq(3)
      expect(user.locked).to be(false)
    end

    it "locks the account after #{User::MAX_AUTH_ATTEMPTS} wrong passwords, like login, and mails the unlock link" do
      log_in!
      ActionMailer::Base.deliveries.clear
      User::MAX_AUTH_ATTEMPTS.times { instance_exec("wrong-password", &attempt) }
      user.reload
      expect(user.locked).to be(true)
      expect(user.locked_until).to be_within(1.minute).of(User::LOCK_DURATION.from_now)
      expect(unlock_mails.size).to eq(1)
    end

    it "refuses even the right password while the lock is in effect, and changes nothing" do
      log_in!
      User::MAX_AUTH_ATTEMPTS.times { instance_exec("wrong-password", &attempt) }
      ActionMailer::Base.deliveries.clear
      instance_exec(password, &attempt)
      expect(flash[:alert] || flash.now[:alert]).to include("locked")
      expect(user.reload.authenticate_password(password)).to be(true)
      expect(user.email).not_to eq("new.addr@example.com")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "shares the counter with failed logins" do
      3.times { post login_authentication_path, params: { username_email: user.username, password: "nope" } }
      log_in! # a successful login resets the counter, as before
      expect(user.reload.auth_attempts).to eq(0)
      4.times { post login_authentication_path, params: { username_email: user.username, password: "nope" } }
      instance_exec("wrong-password", &attempt)
      expect(user.reload.locked).to be(true)
    end

    it "the right password (no lock) resets the counter" do
      log_in!
      2.times { instance_exec("wrong-password", &attempt) }
      instance_exec(password, &attempt)
      expect(user.reload.auth_attempts).to eq(0)
    end
  end

  describe "PATCH /:username/change_password" do
    it_behaves_like "a counted current-password check", ->(pw) { change_password!(pw) }
  end

  describe "POST /change_email" do
    it_behaves_like "a counted current-password check", ->(pw) { change_email!(pw) }
  end
end
