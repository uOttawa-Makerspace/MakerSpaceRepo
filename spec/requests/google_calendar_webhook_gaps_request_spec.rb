# frozen_string_literal: true

require "rails_helper"

# Chunk 18: gaps left by spec/requests/google_calendar_request_spec.rb
# (sync-state / unknown channel / registered / expired / mismatched resource are
# pinned there). Adds: verbs, CSRF, other resource states, no de-duplication.
RSpec.describe "Google calendar webhook (gaps)", type: :request do
  let(:headers) do
    { "X-Goog-Channel-Id" => "chan-g", "X-Goog-Resource-Id" => "res-g", "X-Goog-Resource-State" => "exists" }
  end

  before { GoogleCalendarChannel.create!(channel_id: "chan-g", resource_id: "res-g", expires_at: 1.week.from_now) }

  it "only routes POST (GET is a routing 404)" do
    get "/google/calendar/webhook", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "needs no session, token or CSRF token even with forgery protection on" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    expect { post "/google/calendar/webhook", headers: headers }.to have_enqueued_job(GoogleCalendarSyncJob)
    expect(response).to have_http_status(:ok)
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it "enqueues for every non-sync state (exists, not_exists, anything else)" do
    %w[exists not_exists update].each do |state|
      expect { post "/google/calendar/webhook", headers: headers.merge("X-Goog-Resource-State" => state) }
        .to have_enqueued_job(GoogleCalendarSyncJob)
      expect(response).to have_http_status(:ok)
    end
  end

  it "enqueues one sync job per push (no de-duplication of a burst)" do
    expect { 3.times { post "/google/calendar/webhook", headers: headers } }
      .to have_enqueued_job(GoogleCalendarSyncJob).exactly(3).times
  end

  it "answers the body-less 200 head for the 'sync' state before looking at the ids" do
    post "/google/calendar/webhook", headers: { "X-Goog-Resource-State" => "sync" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
  end
end
