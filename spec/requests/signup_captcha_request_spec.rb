# frozen_string_literal: true

require "rails_helper"

# Signup (POST /new) behind the Cloudflare Turnstile captcha.
#
# TurnstileHelper#verify_turnstile short-circuits to true unless
# TurnstileHelper.verification_enabled? (false under Rails.env.test?),
# so every other signup spec skips the captcha. Here the helper's own
# verification_enabled? predicate is stubbed on for the example (Rails.env itself
# stays untouched) and Cloudflare's siteverify endpoint is
# stubbed with WebMock, so the real verification code (Excon call, JSON parse,
# rescue) runs.
RSpec.describe "Signup captcha (Turnstile siteverify)", type: :request do
  let(:password) { "asa32A353#" }
  let(:siteverify) { TurnstileHelper::TURNSTILE_SITEVERIFY_ENDPOINT }
  let(:attrs) { FactoryBot.attributes_for(:user, :regular_user, password: password) }
  let(:captcha_error) { "Captcha error, try again." }

  before do
    allow(TurnstileHelper).to receive(:verification_enabled?).and_return(true)
    ActionMailer::Base.deliveries.clear
  end

  def sign_up(extra = {})
    post users_path, params: { user: attrs, "cf-turnstile-response" => "token-from-widget" }.merge(extra)
  end

  def expect_no_account
    expect(User.find_by(username: attrs[:username])).to be_nil
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "creates the account when Cloudflare says success, sending the widget token, the secret and the client IP" do
    stub = stub_request(:post, siteverify)
      .with { |req|
        body = JSON.parse(req.body)
        req.headers["Content-Type"] == "application/json" &&
          body["response"] == "token-from-widget" &&
          body["secret"] == Rails.application.credentials[:test][:cloudflare][:turnstile][:secret_key] &&
          body["remoteip"] == "127.0.0.1"
      }
      .to_return(status: 200, body: { success: true }.to_json)

    expect { perform_enqueued_jobs { sign_up } }.to change(User, :count).by(1)
    expect(stub).to have_been_requested.once
    expect(response).to redirect_to(root_path)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "refuses the signup when Cloudflare says success:false: 422, captcha alert, no user, no mail" do
    stub = stub_request(:post, siteverify)
      .to_return(status: 200, body: { success: false, "error-codes" => ["invalid-input-response"] }.to_json)

    expect { sign_up }.not_to change(User, :count)
    expect(stub).to have_been_requested.once
    expect(response).to have_http_status(:unprocessable_content)
    expect(flash[:alert]).to eq(captcha_error)
    expect_no_account
  end

  it "answers a JSON signup with a captcha failure and creates nothing" do
    stub_request(:post, siteverify).to_return(status: 200, body: { success: false }.to_json)

    expect { post users_path, params: { user: attrs, "cf-turnstile-response" => "x" }, as: :json }.not_to change(User, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)).to eq("errors" => "captcha failure")
    expect_no_account
  end

  [[:to_timeout, "times out"], [:to_raise, "cannot be reached"]].each do |matcher, what|
    it "refuses the signup (captcha error, no account) and reports the error when Cloudflare #{what}" do
      stub = stub_request(:post, siteverify)
      matcher == :to_raise ? stub.to_raise(Excon::Error::Socket.new(Errno::ECONNREFUSED.new)) : stub.to_timeout
      expect(Rails.error).to receive(:report).with(kind_of(Excon::Error), hash_including(handled: true))

      expect { sign_up }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq(captcha_error)
      expect_no_account
    end
  end

  it "refuses the signup when Cloudflare answers with a non-JSON body (rescued, logged, treated as failure)" do
    stub_request(:post, siteverify).to_return(status: 502, body: "<html>Bad gateway</html>")
    expect(Rails.logger).to receive(:warn).at_least(:once)

    expect { sign_up }.not_to change(User, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(flash[:alert]).to eq(captcha_error)
    expect_no_account
  end

  it "refuses the signup when the JSON has no success key" do
    stub_request(:post, siteverify).to_return(status: 200, body: "{}")

    expect { sign_up }.not_to change(User, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect_no_account
  end
end
