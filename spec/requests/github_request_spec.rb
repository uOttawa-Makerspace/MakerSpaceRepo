# frozen_string_literal: true

require "rails_helper"

# Chunk 18: GithubController (link a user's GitHub account via OAuth). There is
# no webhook and no signature path in this controller: the only inbound surface
# is the OAuth callback. GitHub is stubbed at the HTTP boundary (WebMock).
#
# Gates: before_action :signed_in applies to every action, callback included
# (it used User.find(session[:user_id]), which bypassed the session rules).
RSpec.describe "GitHub integration", type: :request do
  include Chunk18Helpers

  let(:token_url) { "https://github.com/login/oauth/access_token" }

  def stub_token_exchange(body, status = 200)
    stub_request(:post, token_url).to_return(
      status: status, body: body.to_json, headers: { "Content-Type" => "application/json" }
    )
  end

  before do
    stub_const("GithubController::CLIENT_ID", "gh-client")
    stub_const("GithubController::CLIENT_SECRET", "gh-secret")
  end

  describe "GET /github/authorize" do
    it "redirects a guest to the login page" do
      get "/github/authorize"
      expect(response).to redirect_to(login_path(back_to: "/github/authorize"))
    end

    it "is a 500 for a signed-in user: Octokit 10 has no Client#authorize_url" do
      # WART(D-R19): the controller calls Octokit::Client#authorize_url, which no longer exists in octokit 10, so the OAuth flow cannot even start (500); the redirect it would build has no `state` parameter either
      c18_sign_in(:regular)
      get "/github/authorize"
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "GET /github/callback" do
    it "for a guest redirects to login before any call to GitHub" do
      # FIXED: was a RecordNotFound 404 from User.find(session[:user_id])
      get "/github/callback", params: { code: "abc" }
      expect(response).to redirect_to(login_path(back_to: "/github/callback?code=abc"))
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it "for a session whose user was deactivated or revoked is treated as a guest" do
      user = c18_sign_in(:regular)
      user.update_columns(active: false)
      get "/github/callback", params: { code: "abc" }
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/login")
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it "accepts a Bearer JWT caller too (current_user, no session needed)" do
      user = create(:user, :regular_user)
      stub_token_exchange(access_token: "gho_jwt", token_type: "bearer")
      get "/github/callback", params: { code: "abc" }, headers: { "Authorization" => "Bearer #{user.token}" }
      expect(response).to redirect_to(settings_admin_path)
      expect(user.reload.access_token).to eq("gho_jwt")
    end

    it "exchanges the code (client id/secret from ENV constants), stores the token on the session user and redirects to the admin settings" do
      user = c18_sign_in(:regular)
      stub_token_exchange(access_token: "gho_abc123", token_type: "bearer")
      get "/github/callback", params: { code: "the-code" }
      expect(response).to redirect_to(settings_admin_path)
      expect(user.reload.access_token).to eq("gho_abc123")
      expect(a_request(:post, token_url).with { |req|
        JSON.parse(req.body) == { "code" => "the-code", "client_id" => "gh-client", "client_secret" => "gh-secret" }
      }).to have_been_made.once
    end

    it "accepts any code for any signed-in role without a state check and overwrites an existing token" do
      # WART(D-R20): no OAuth `state` is generated or verified (CSRF/login-CSRF): anyone who can get a signed-in user to open /github/callback?code=<attacker's code> binds the attacker's GitHub account to the victim; the callback also needs no role
      user = c18_sign_in(:regular)
      user.update!(access_token: "victim-existing-token")
      stub_token_exchange(access_token: "attacker-token")
      get "/github/callback", params: { code: "attacker-code", state: "ignored" }
      expect(user.reload.access_token).to eq("attacker-token")
    end

    it "a GitHub error response (bad code) wipes the stored token and still redirects as if it worked" do
      # WART(D-R21): the error payload has no access_token, so `.access_token` is nil and update writes nil over the user's existing token, with no error shown
      user = c18_sign_in(:regular)
      user.update!(access_token: "still-good-token")
      stub_token_exchange(error: "bad_verification_code")
      get "/github/callback", params: { code: "expired" }
      expect(response).to redirect_to(settings_admin_path)
      expect(user.reload.access_token).to be_nil
    end

    it "a transport failure from GitHub is a 500 and leaves the token alone" do
      user = c18_sign_in(:regular)
      user.update!(access_token: "keep")
      stub_request(:post, token_url).to_timeout
      get "/github/callback", params: { code: "abc" }
      expect(response).to have_http_status(:internal_server_error)
      expect(user.reload.access_token).to eq("keep")
    end
  end

  describe "GET /github/repositories" do
    it "answers a JSON guest with the literal body \"redirect\" (200), not a redirect" do
      get "/github/repositories.json"
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("redirect")
    end

    it "lists the repository names (JSON) for a user with a token, using that token" do
      user = c18_sign_in(:regular)
      user.update!(access_token: "gho_tok")
      stub_request(:get, "https://api.github.com/user/repos")
        .with(headers: { "Authorization" => "token gho_tok" })
        .to_return(status: 200, body: [{ name: "alpha" }, { name: "beta" }].to_json,
                   headers: { "Content-Type" => "application/json" })
      get "/github/repositories.json"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(%w[alpha beta])
    end

    it "is a 500 for a user who never linked GitHub (nil client)" do
      # WART(D-R22): github_client returns nil when the user has no access_token and the action calls .repos on it
      c18_sign_in(:regular)
      get "/github/repositories.json"
      expect(response).to have_http_status(:internal_server_error)
    end

    it "has only a JSON template: the html variant is a 406" do
      user = c18_sign_in(:regular)
      user.update!(access_token: "gho_tok")
      stub_request(:get, "https://api.github.com/user/repos").to_return(
        status: 200, body: "[]", headers: { "Content-Type" => "application/json" }
      )
      get "/github/repositories"
      expect(response).to have_http_status(:not_acceptable)
    end
  end

  describe "GET /github/unauthorize" do
    it "redirects a guest to the login page" do
      get "/github/unauthorize"
      expect(response).to redirect_to(login_path(back_to: "/github/unauthorize"))
    end

    it "is a 500 and keeps the token because the Octokit client has no application credentials" do
      # WART(D-R23): `github` is Octokit::Client.new with no client_id/secret, and revoking needs them (Octokit::ApplicationCredentialsRequired), so unlinking GitHub always fails unless OCTOKIT_CLIENT_ID/SECRET are set globally
      user = c18_sign_in(:regular)
      user.update!(access_token: "gho_tok")
      get "/github/unauthorize"
      expect(response).to have_http_status(:internal_server_error)
      expect(user.reload.access_token).to eq("gho_tok")
    end

    it "with global Octokit application credentials it revokes at GitHub, clears the token and flashes a notice" do
      user = c18_sign_in(:regular)
      user.update!(access_token: "gho_tok")
      begin
        Octokit.configure { |c| c.client_id = "gh-client"; c.client_secret = "gh-secret" }
        revoke = stub_request(:delete, "https://api.github.com/applications/gh-client/token")
                 .with(body: { access_token: "gho_tok" }.to_json)
                 .to_return(status: 204)
        get "/github/unauthorize"
        expect(revoke).to have_been_requested.once
      ensure
        Octokit.reset!
      end
      expect(response).to redirect_to(settings_admin_path)
      expect(flash[:notice]).to eq("Successfully revoked access to github account.")
      expect(user.reload.access_token).to be_nil
    end
  end
end
