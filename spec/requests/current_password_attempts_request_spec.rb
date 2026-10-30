# frozen_string_literal: true

require "rails_helper"

# change_password and change_email re-authenticate the signed-in user with the
# current password. Guessing it is throttled per signed-in user and credential
# generation (UsersController::REAUTH_MAX_ATTEMPTS, shared by both actions). Each
# submitted current password is counted atomically (RateLimitCounter) BEFORE it is
# verified; a correct one clears the count; a blank one and a bad new value are
# not guesses. Over the limit every credential of the user ends (cookie session,
# Bearer JWT, refresh tokens) and bcrypt is not run; the owner can sign in again
# and carry on. Re-authentication never touches the login lockout (auth_attempts,
# locked): a stranger's failed logins cannot stop the owner from changing their
# password, and changing it clears a timed lockout.
RSpec.describe "Current-password re-authentication", type: :request do
  let(:password) { "asa32A353#" }
  let(:new_password) { "NewPassw0rd!x#9" }
  let!(:user) { create(:user, :regular_user) }
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

  it "counts the attempt BEFORE the password is verified, so parallel guesses cannot all pass" do
    log_in!
    counted_while_verifying = []
    allow_any_instance_of(User).to receive(:authenticate_password).and_wrap_original do |m, *args|
      counted_while_verifying << RateLimitCounter.where("key LIKE 'reauth/%'").pluck(:count)
      m.call(*args)
    end
    change_password!("wrong-password")
    expect(counted_while_verifying).to eq([[1]])
  end

  it "runs no password check once the budget is spent" do
    log_in!
    5.times { change_password!("wrong-password") }
    expect_any_instance_of(User).not_to receive(:authenticate_password)
    change_password!(password)
    expect(response).to redirect_to(login_path)
  end

  describe "revoking on exhaustion" do
    it "a burst of wrong guesses bumps token_version exactly once" do
      log_in!
      before = user.reload.token_version
      9.times { change_password!("wrong-password") }
      expect(user.reload.token_version).to eq(before + 1)
    end

    # Count and bump are one transaction; any failure rolls both back and the request
    # fails BEFORE the password is checked (fail closed). No adapter SQL is stubbed.
    shared_examples "a fail-closed re-authentication" do |failing_call|
      it "answers with an error, runs no password check, and leaves the counter and token_version unchanged" do
        log_in!
        limit = UsersController::REAUTH_MAX_ATTEMPTS
        limit.times { change_password!("wrong-password") }
        before = user.reload.token_version
        key = "reauth/#{user.id}/#{before}"
        counted = RateLimitCounter.find_by!(key: key).count
        instance_exec(&failing_call)
        expect_any_instance_of(User).not_to receive(:authenticate_password)
        change_password!(password)
        expect(response).to have_http_status(:internal_server_error)
        expect(RateLimitCounter.find_by!(key: key).count).to eq(counted)
        expect(user.reload.token_version).to eq(before)
      end
    end

    describe "when counting fails" do
      it_behaves_like "a fail-closed re-authentication",
                      -> { allow(RateLimitCounter).to receive(:increment).and_raise(ActiveRecord::StatementInvalid, "killed") }
    end

    describe "when the bump fails" do
      it_behaves_like "a fail-closed re-authentication",
                      -> { allow_any_instance_of(User).to receive(:bump_token_version!).and_raise(ActiveRecord::StatementInvalid, "killed") }
    end

    describe "when the refresh-token bookkeeping fails after the commit" do
      it "keeps the bump: the session ends, every credential is dead, the error is reported" do
        log_in!
        pair = api_token_pair(user, password)
        legacy = user.token
        refresh = ApiRefreshToken.find_by_raw(pair["refresh_token"])
        5.times { change_password!("wrong-password") }
        before = user.reload.token_version
        allow(ApiRefreshToken).to receive(:revoke_all_for!).and_raise(ActiveRecord::StatementInvalid, "killed")
        expect(Rails.error).to receive(:report).with(instance_of(ActiveRecord::StatementInvalid), handled: true)

        change_password!("wrong-password")

        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to eq(limit_message)
        expect(user.reload.token_version).to eq(before + 1)
        expect(signed_in?).to be(false)
        expect(JwtAuthenticator.user_for("Bearer #{legacy}")).to be_nil
        expect(ApiAccessToken.user_for("Bearer #{pair['access_token']}")).to be_nil
        expect(refresh.reload.revoked_at).to be_nil # the rows were not marked ...
        expect(refresh.usable?).to be(false)        # ... and are dead by token_version
      end
    end
  end

  it "signs out, without a 500, when the account vanished before the exhausting bump (compare-and-set false)" do
    log_in!
    5.times { change_password!("wrong-password") }
    allow(RateLimitCounter).to receive(:increment).and_wrap_original do |m, *args, **opts|
      User.unscoped.where(id: user.id).update_all(deleted: true)
      m.call(*args, **opts)
    end
    expect_any_instance_of(User).not_to receive(:authenticate_password)
    change_password!("wrong-password")
    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(limit_message)
    expect(signed_in?).to be(false)
  end

  it "a password change that fails because the row is gone signs out and redirects to login without a second raise" do
    log_in!
    allow_any_instance_of(User).to receive(:store_new_password!) do |u|
      User.where(id: u.id).delete_all
      raise ActiveRecord::StatementInvalid, "row gone"
    end
    change_password!(password)
    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq("This account no longer exists. Please sign in again.")
    expect(signed_in?).to be(false)
  end

  it "a password change that fails because the account was soft-deleted meanwhile signs out with the neutral message" do
    log_in!
    allow_any_instance_of(User).to receive(:store_new_password!) do |u|
      User.unscoped.where(id: u.id).update_all(deleted: true)
      raise ActiveRecord::StatementInvalid, "row changed"
    end
    change_password!(password)
    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq("This account no longer exists. Please sign in again.")
    expect(signed_in?).to be(false)
  end

  describe "exhaustion ends every credential, not just the cookie session" do
    let(:pair) { api_token_pair(user, password) }

    def bearer_change_email(token, current)
      post change_email_users_path,
           params: { new_email: "new.addr@example.com", confirm_new_email: "new.addr@example.com",
                     current_password: current }.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json",
                      "Authorization" => "Bearer #{token}" }
    end

    it "a legacy Bearer JWT reaches the endpoint, and exhausting it kills that JWT" do
      token = user.token
      bearer_change_email(token, "wrong-password")
      expect(response).to have_http_status(:redirect).or have_http_status(:ok)
      expect(response).not_to redirect_to(login_path)
      5.times { bearer_change_email(token, "wrong-password") }
      expect(response).to redirect_to(login_path)
      get check_signed_in_path, headers: { "Authorization" => "Bearer #{token}" }
      expect(response.parsed_body["signed_in"]).not_to eq("true")
    end

    it "revokes the user's /api/v1 access and refresh tokens, and a cookie session" do
      log_in!
      access, refresh = pair.values_at("access_token", "refresh_token")
      6.times { change_password!("wrong-password") }
      expect(signed_in?).to be(false)

      get "/api/v1/session", headers: { "Authorization" => "Bearer #{access}" }
      expect(response).to have_http_status(:unauthorized)
      post "/api/v1/session/refresh", params: { refresh_token: refresh }.to_json,
                                      headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "signing in again starts a fresh budget" do
      6.times { change_password!("wrong-password") } # a hijacked cookie session is killed
      log_in!
      5.times { change_password!("wrong-password") }
      expect(signed_in?).to be(true)
    end
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
