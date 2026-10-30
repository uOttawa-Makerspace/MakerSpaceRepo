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
    RateLimitCounter.delete_all # the logins above counted against the IP limit too
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
    tokens = (post "/api/v1/session", params: { login: user.username, password: password }.to_json,
                                       headers: { "CONTENT_TYPE" => "application/json" }) && response.parsed_body
    before = user.reload.token_version
    5.times { wrong_guess(sessions.first) }

    # Every request has loaded @user and counted its attempt before any bumps.
    barrier = Queue.new
    allow(RateLimitCounter).to receive(:increment).and_wrap_original do |m, *args, **opts|
      m.call(*args, **opts).tap do
        barrier << true
        sleep 0.01 until barrier.size >= threads
      end
    end

    results = sessions.map do |sess|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { wrong_guess(sess) && sess.response.status }
      rescue StandardError => e
        e
      end
    end.map(&:value)

    expect(results).to all(eq(302))
    expect(User.find(user.id).token_version).to eq(before + 1)
    get "/api/v1/session", headers: { "Authorization" => "Bearer #{tokens['access_token']}" }
    expect(response).to have_http_status(:unauthorized)
    expect(ApiRefreshToken.where(user_id: user.id, revoked_at: nil)).to be_empty
    sessions.each do |sess|
      sess.get "/check_signed_in"
      expect(sess.response.parsed_body["signed_in"]).not_to eq("true")
    end
  end
end
