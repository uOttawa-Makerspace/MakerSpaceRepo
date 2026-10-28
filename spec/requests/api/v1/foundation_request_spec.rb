# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/v1 foundation", type: :request do
  it "answers unknown paths with the JSON 404 and no cookie" do
    get "/api/v1/nope/at/all"
    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/json")
    expect(response.parsed_body).to eq("error" => { "code" => "not_found", "message" => "Not found" })
    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "does not demand a CSRF token on writes (404 here, not 422 from forgery protection)" do
    post "/api/v1/nope"
    expect(response).to have_http_status(:not_found)
  end

  it "answers malformed JSON with a 400 JSON error" do
    post "/api/v1/nope", params: "{bad", headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig("error", "code")).to eq("bad_request")
  end
end

RSpec.describe "/api/v1 JSON 500", type: :request do
  let(:user) { create(:user) }

  around do |example|
    previous = Api::V1::BaseController.json_internal_errors
    example.run
  ensure
    Api::V1::BaseController.json_internal_errors = previous
  end

  before { allow(ApiAccessToken).to receive(:user_for).and_raise(RuntimeError, "boom") }

  it "renders the uniform JSON body and reports the error when the flag is on" do
    Api::V1::BaseController.json_internal_errors = true
    expect(Rails.error).to receive(:report).with(an_instance_of(RuntimeError), hash_including(handled: true))
    get "/api/v1/session", headers: { "Authorization" => "Bearer x" }
    expect(response).to have_http_status(:internal_server_error)
    expect(response.parsed_body).to eq("error" => { "code" => "internal_error", "message" => "Something went wrong" })
    expect(response.body).not_to include("boom")
  end

  it "is off in the test environment by default (errors stay visible to specs)" do
    expect(Api::V1::BaseController.json_internal_errors).to eq(!Rails.env.test?)
    Api::V1::BaseController.json_internal_errors = false
    get "/api/v1/session", headers: { "Authorization" => "Bearer x" }
    expect(response).to have_http_status(:internal_server_error)
    expect(response.media_type).not_to eq("application/json") # Rails own error page, not ours
  end
end
