# frozen_string_literal: true

require "rails_helper"

# A real burst: several requests of one user, every one over the re-authentication
# limit, each with a @user loaded BEFORE any of them revokes. Exactly one changes
# token_version (+1) and every credential is dead afterwards.
RSpec.describe "Current-password exhaustion under concurrency", type: :request do
  self.use_transactional_tests = false

  let(:password) { "asa32A353#" }
  let!(:user) { create(:user, :regular_user) }
  let(:threads) { 5 }

  after do
    ApiRefreshToken.where(user_id: user.id).delete_all
    User.unscoped.where(id: user.id).delete_all
  end

  def session_for_user
    open_session.tap do |s|
      s.post "/login_authentication", params: { username_email: user.username, password: password }
      expect(s.response).to have_http_status(:redirect)
    end
  end

  def wrong_guess(sess)
    sess.patch Rails.application.routes.url_helpers.change_password_user_path(user.username),
               params: { user: { old_password: "wrong-password", password: "NewPassw0rd!x#9",
                                 password_confirmation: "NewPassw0rd!x#9" } }
  end

  it "bumps token_version exactly once and ends the cookie sessions and the tokens" do
    sessions = Array.new(threads) { session_for_user }
    tokens = api_token_pair(user, password)
    before = user.reload.token_version
    5.times { wrong_guess(sessions.first) }

    # Every request has loaded @user, and all of them reach the counter together.
    barrier = Queue.new
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    allow(RateLimitCounter).to receive(:increment).and_wrap_original do |m, *args, **opts|
      barrier << true
      until barrier.size >= threads
        raise "barrier: not every request arrived within 10s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.01
      end
      m.call(*args, **opts)
    end

    disconnects = []
    allow_any_instance_of(User).to receive(:disconnect_cable!) { disconnects << true }

    results = sessions.map do |sess|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { wrong_guess(sess) && [sess.response.location, sess.flash[:alert]] }
      rescue StandardError => e
        e
      end
    end.map(&:value)

    expect(results).to all(eq(["http://www.example.com#{login_path}", UsersController::REAUTH_LIMIT_ALERT]))
    expect(User.find(user.id).token_version).to eq(before + 1)
    expect(disconnects.size).to eq(1) # the websockets are closed by the one request that bumped
    get "/api/v1/session", headers: { "Authorization" => "Bearer #{tokens['access_token']}" }
    expect(response).to have_http_status(:unauthorized)
    expect(ApiRefreshToken.where(user_id: user.id, revoked_at: nil)).to be_empty
    sessions.each do |sess|
      sess.get "/check_signed_in"
      expect(sess.response.parsed_body["signed_in"]).not_to eq("true")
    end
  end

  describe "a password change racing a change on another connection" do
    let(:new_password) { "NewPassw0rd!x#9" }

    def change_password!(sess)
      sess.patch Rails.application.routes.url_helpers.change_password_user_path(user.username),
                 params: { user: { old_password: password, password: new_password, password_confirmation: new_password } }
    end

    # Runs the block on another connection (committed) between the request's load and its store.
    def between_load_and_store(&block)
      allow_any_instance_of(User).to receive(:plaintext_password_problems).and_wrap_original do |m, *args|
        Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }.value
        m.call(*args)
      end
    end

    it "an admin soft-delete: the password is not changed, no email is sent, the request signs out" do
      sess = session_for_user
      digest = User.find(user.id).password
      between_load_and_store { User.find(user.id).soft_delete! }
      expect(MsrMailer).not_to receive(:confirm_password_change)

      change_password!(sess)

      expect(sess.response.location).to eq("http://www.example.com#{login_path}")
      expect(User.unscoped.find(user.id).password).to eq(digest)
      sess.get "/check_signed_in"
      expect(sess.response.parsed_body["signed_in"]).not_to eq("true")
    end

    it "a revocation committed since the load: the password is not changed, no email, signed out, not re-synced" do
      sess = session_for_user
      digest = User.find(user.id).password
      version = User.find(user.id).token_version
      between_load_and_store { User.find(user.id).bump_token_version! }
      expect(MsrMailer).not_to receive(:confirm_password_change)

      change_password!(sess)

      expect(sess.response.location).to eq("http://www.example.com#{login_path}")
      row = User.find(user.id)
      expect([row.password, row.token_version]).to eq([digest, version + 1])
      sess.get "/check_signed_in"
      expect(sess.response.parsed_body["signed_in"]).not_to eq("true")
    end
  end
end
