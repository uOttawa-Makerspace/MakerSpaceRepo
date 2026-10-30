# frozen_string_literal: true

require "rails_helper"

# FIXED(G01 / CORS): origins are exact strings or fully anchored regexps. The
# credentialed allow-list (lib/cors_origins.rb) is per environment: the staff app
# and Design Day everywhere, the Pages previews on staging only, localhost:5173 in
# development/test only (spec/lib/cors_origins_spec.rb covers each environment).
# This is the test env.
RSpec.describe "CORS origin allow-list", type: :request do
  def acao(origin)
    get "/admin/design_day/data", headers: { "Origin" => origin }
    response.headers["Access-Control-Allow-Origin"]
  end

  [
    "https://app.makerepo.com",
    "https://designday.makerepo.com",
    "http://localhost:5173"
  ].each do |origin|
    it "allows #{origin} (echoed, with credentials)" do
      expect(acao(origin)).to eq(origin)
      expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
    end
  end

  # previews are staging-only; github.io is used by no frontend
  [
    "https://abc123.makerepo-app.pages.dev",
    "https://feature-x.design-day-react.pages.dev",
    "https://uottawa-makerspace.github.io"
  ].each do |origin|
    it "does not allow #{origin} outside staging" do
      expect(acao(origin)).to be_nil
    end
  end

  [
    "https://app.makerepo.com.attacker.io",
    "https://evil-app.makerepo.com.attacker.io",
    "https://evilapp.makerepo.com",
    "https://designday.makerepo.com.evil.com",
    "http://app.makerepo.com",
    "https://uottawa-makerspace.github.io.evil.com",
    "https://x.makerepo-app.pages.dev.evil.com",
    "https://x.design-day-react.pages.dev.evil.com",
    "https://evil.com/x.makerepo-app.pages.dev",
    "https://x.makerepo-appXpages.dev",
    "http://localhost:51730",
    "null"
  ].each do |origin|
    it "does not allow #{origin}" do
      expect(acao(origin)).to be_nil
    end
  end
end

# /api/* has its own resource: same anchored origins, no credentials, an explicit
# header and method list. The credentialed catch-all must not answer /api paths.
RSpec.describe "CORS for /api/*", type: :request do
  def preflight(origin, path: "/api/v1/session", method: "POST", headers: "authorization,content-type")
    process :options, path, headers: {
      "Origin" => origin,
      "Access-Control-Request-Method" => method,
      "Access-Control-Request-Headers" => headers
    }
  end

  ["https://app.makerepo.com", "http://localhost:5173"].each do |origin|
    it "answers the preflight for #{origin} without credentials" do
      preflight(origin)
      expect(response.headers["Access-Control-Allow-Origin"]).to eq(origin)
      expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
      expect(response.headers["Access-Control-Allow-Headers"].downcase).to include("authorization", "content-type")
      expect(response.headers["Access-Control-Allow-Methods"]).to include("POST").and include("DELETE")
      expect(response.headers["Access-Control-Max-Age"]).to eq("600")
    end
  end

  it "exposes X-Truncated to the apps on /api responses" do
    get "/api/v1/session", headers: { "Origin" => "https://app.makerepo.com" }
    expect(response.headers["Access-Control-Expose-Headers"]).to include("X-Truncated")
  end

  it "echoes the origin on an actual request, with no credentials header" do
    get "/api/v1/session", headers: { "Origin" => "https://app.makerepo.com" }
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("https://app.makerepo.com")
    expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
  end

  it "refuses headers outside the list in the preflight" do
    preflight("https://app.makerepo.com", headers: "x-evil")
    expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
  end

  [
    "https://app.makerepo.com.attacker.io",
    "https://evilapp.makerepo.com",
    "http://app.makerepo.com",
    "https://x.makerepo-app.pages.dev.evil.com",
    "null"
  ].each do |origin|
    it "does not allow #{origin}" do
      preflight(origin)
      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
      get "/api/v1/session", headers: { "Origin" => origin }
      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end
  end

  it "leaves the credentialed config for non-API paths unchanged" do
    get "/admin/design_day/data", headers: { "Origin" => "https://app.makerepo.com" }
    expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
  end
end

# The Design Day resource matches exactly /api/v1/design_day (optional trailing slash): a
# look-alike path such as /api/v1/design_day_x is an ordinary /api path.
RSpec.describe "CORS Design Day path anchoring", type: :request do
  let(:dd) { "https://designday.makerepo.com" }
  let(:staff) { "https://app.makerepo.com" }

  def acao = response.headers["Access-Control-Allow-Origin"]

  ["/api/v1/design_day", "/api/v1/design_day/"].each do |path|
    it "answers the Design Day origin on #{path}" do
      get path, headers: { "Origin" => dd }
      expect(acao).to eq(dd)
      expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
    end

    it "does not answer the staff app on #{path}" do
      get path, headers: { "Origin" => staff }
      expect(acao).to be_nil
    end
  end

  ["/api/v1/design_day_x", "/api/v1/design_dayx", "/api/v1/design_day/x"].each do |path|
    it "treats #{path} as a normal /api path (staff app gets the /api headers, no credentials)" do
      get path, headers: { "Origin" => staff }
      expect(acao).to eq(staff)
      expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
      # the /api block exposes exactly X-Truncated (the Design Day block exposes nothing)
      expect(response.headers["Access-Control-Expose-Headers"].to_s).to eq("X-Truncated")
    end
  end

  it "gives an origin outside the allow-list nothing on /api/v1/design_day_x" do
    get "/api/v1/design_day_x", headers: { "Origin" => "https://evil.example" }
    expect(acao).to be_nil
  end
end
