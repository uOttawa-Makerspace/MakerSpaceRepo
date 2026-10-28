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
