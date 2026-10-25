# frozen_string_literal: true

require "rails_helper"

# Characterization spec for GoogleCalendarController#webhook (firewall-less
# POST /google/calendar/webhook). Pins the header-driven contract:
#   X-Goog-Resource-State == "sync"  → 200 (no auth, no enqueue)
#   unknown channel/resource pair    → 401
#   valid channel row                → 200 + enqueues GoogleCalendarSyncJob

RSpec.describe "Google calendar webhook", type: :request do
  let(:webhook_path) { "/google/calendar/webhook" }

  def post_webhook(headers)
    post webhook_path, headers: headers
  end

  it "answers 200 head for the initial 'sync' push without any channel" do
    post_webhook({
      "X-Goog-Channel-Id" => "whatever",
      "X-Goog-Resource-Id" => "whatever",
      "X-Goog-Resource-State" => "sync"
    })
    expect(response.status).to eq(200)
    expect(response.body).to be_empty
    expect(GoogleCalendarSyncJob).not_to have_been_enqueued
  end

  it "answers 401 (logged) when headers name no known channel" do
    post_webhook({
      "X-Goog-Channel-Id" => "no-such-channel",
      "X-Goog-Resource-Id" => "no-such-resource",
      "X-Goog-Resource-State" => "exists"
    })
    expect(response.status).to eq(401)
    expect(GoogleCalendarSyncJob).not_to have_been_enqueued
  end

  it "enqueues GoogleCalendarSyncJob for a registered channel pair" do
    GoogleCalendarChannel.create!(
      channel_id: "chan-1", resource_id: "res-1",
      expires_at: 1.week.from_now
    )

    expect {
      post_webhook({
        "X-Goog-Channel-Id" => "chan-1",
        "X-Goog-Resource-Id" => "res-1",
        "X-Goog-Resource-State" => "exists"
      })
    }.to have_enqueued_job(GoogleCalendarSyncJob)

    expect(response.status).to eq(200)
  end

  # WART(D-B41): the webhook never checks channel expiry (nor the channel
  # token), so an expired channel row is accepted and enqueues a sync.
  it "accepts an EXPIRED channel pair and enqueues the sync job anyway" do
    GoogleCalendarChannel.create!(
      channel_id: "chan-old", resource_id: "res-old",
      expires_at: 1.week.ago
    )

    expect {
      post_webhook({
        "X-Goog-Channel-Id" => "chan-old",
        "X-Goog-Resource-Id" => "res-old",
        "X-Goog-Resource-State" => "exists"
      })
    }.to have_enqueued_job(GoogleCalendarSyncJob)

    expect(response.status).to eq(200)
  end

  it "401s when the row's resource_id mismatches even if channel_id exists" do
    GoogleCalendarChannel.create!(
      channel_id: "chan-2", resource_id: "res-2",
      expires_at: 1.week.from_now
    )
    post_webhook({
      "X-Goog-Channel-Id" => "chan-2",
      "X-Goog-Resource-Id" => "res-mismatched",
      "X-Goog-Resource-State" => "exists"
    })
    expect(response.status).to eq(401)

    # a bare POST (no Google headers at all) is equally 401
    post webhook_path
    expect(response.status).to eq(401)
  end
end
