# frozen_string_literal: true

require "rails_helper"

# Contract: doc/api/v1/design_day.md
RSpec.describe "GET /api/v1/design_day", type: :request do
  let(:allowed) { ["https://designday.makerepo.com", "https://feature-x.design-day-react.pages.dev"] }
  let(:refused) do
    ["https://app.makerepo.com", "http://localhost:5173", "https://abc.makerepo-app.pages.dev",
     "https://uottawa-makerspace.github.io", "https://designday.makerepo.com.evil.com",
     "https://x.design-day-react.pages.dev.evil.com", "http://designday.makerepo.com", "null"]
  end

  def body = response.parsed_body

  after do
    DesignDay.unscoped.find_each(&:destroy)
  end

  context "with a configured design day" do
    let!(:design_day) { create(:design_day, day: Date.new(2026, 3, 14), is_live: true, sheet_key: "KEY123", show_floorplans: true) }

    it "is public and answers exactly the inventory field list" do
      get "/api/v1/design_day"
      expect(response).to have_http_status(:ok)
      expect(response.headers["Set-Cookie"]).to be_nil
      expect(body.keys).to eq(%w[year semester day sheet_key show_floorplans floorplan_urls floorplan_titles schedules])
      expect(body).to include("year" => 2026, "semester" => "winter", "day" => "2026-03-14",
                              "sheet_key" => "KEY123", "show_floorplans" => true)
      expect(body["floorplan_urls"].size).to eq(1)
      expect(body["floorplan_urls"].first).to start_with("http")
      expect(body["floorplan_titles"].size).to eq(1)
      expect(body["schedules"].size).to eq(10)
      expect(body["schedules"].map(&:keys).uniq).to eq([%w[start end title_en title_fr event_for]])
      expect(body["schedules"].map { |s| s["event_for"] }.uniq).to contain_exactly("student", "judge")
    end

    it "carries the same values as the legacy data endpoint" do
      get "/admin/design_day/data"
      legacy = JSON.parse(response.body)
      get "/api/v1/design_day"
      expect(body.slice("year", "semester", "day", "sheet_key", "show_floorplans"))
        .to eq(legacy.slice("year", "semester", "day", "sheet_key", "show_floorplans"))
      expect(body["schedules"].map { |s| s.slice("start", "end", "title_en", "title_fr", "event_for") })
        .to eq(legacy["design_day_schedules"].map { |s| s.slice("start", "end", "title_en", "title_fr", "event_for") })
    end

    it "does not run a query per schedule" do
      queries = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| queries << p[:sql] if p[:sql] =~ /design_day_schedules/ }
      get "/api/v1/design_day"
      ActiveSupport::Notifications.unsubscribe(sub)
      expect(queries.size).to eq(1)
    end

    it "ignores a Bearer token and any cookie" do
      get "/api/v1/design_day", headers: { "Authorization" => "Bearer nonsense" }
      expect(response).to have_http_status(:ok)
    end
  end

  it "answers empty arrays, and writes nothing, when no design day exists" do
    expect { get "/api/v1/design_day" }.not_to change(DesignDay.unscoped, :count)
    expect(response).to have_http_status(:ok)
    expect(body).to include("floorplan_urls" => [], "floorplan_titles" => [], "schedules" => [], "sheet_key" => "")
  end

  describe "CORS" do
    it "echoes an allowed Design Day origin, without credentials" do
      allowed.each do |origin|
        get "/api/v1/design_day", headers: { "Origin" => origin }
        expect(response.headers["Access-Control-Allow-Origin"]).to eq(origin)
        expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
      end
    end

    it "answers the preflight for an allowed origin (GET only)" do
      process :options, "/api/v1/design_day", headers: {
        "Origin" => allowed.first, "Access-Control-Request-Method" => "GET"
      }
      expect(response.headers["Access-Control-Allow-Origin"]).to eq(allowed.first)
      expect(response.headers["Access-Control-Allow-Methods"]).to eq("GET, OPTIONS")
      expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
    end

    it "sends no CORS headers to any other origin, including the staff app and localhost" do
      refused.each do |origin|
        get "/api/v1/design_day", headers: { "Origin" => origin }
        expect(response.headers).not_to have_key("Access-Control-Allow-Origin"), origin
        expect(response.headers).not_to have_key("Access-Control-Allow-Credentials"), origin
        process :options, "/api/v1/design_day", headers: {
          "Origin" => origin, "Access-Control-Request-Method" => "GET"
        }
        expect(response.headers).not_to have_key("Access-Control-Allow-Origin"), origin
      end
    end

    it "does not widen the other /api/v1 paths to the Design Day origin's detriment" do
      get "/api/v1/spaces", headers: { "Origin" => "https://app.makerepo.com" }
      expect(response.headers["Access-Control-Allow-Origin"]).to eq("https://app.makerepo.com")
    end
  end
end
