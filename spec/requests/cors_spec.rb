# frozen_string_literal: true

require "rails_helper"

# FIXED(G01 / CORS): origins are exact strings or fully anchored regexps. The
# credentialed allow-list is the React staff app, Design Day and their previews.
RSpec.describe "CORS origin allow-list", type: :request do
  def acao(origin)
    get "/admin/design_day/data", headers: { "Origin" => origin }
    response.headers["Access-Control-Allow-Origin"]
  end

  [
    "https://app.makerepo.com",
    "https://designday.makerepo.com",
    "https://uottawa-makerspace.github.io",
    "http://localhost:5173",
    "https://abc123.makerepo-app.pages.dev",
    "https://feature-x.design-day-react.pages.dev"
  ].each do |origin|
    it "allows #{origin} (echoed, with credentials)" do
      expect(acao(origin)).to eq(origin)
      expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
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
