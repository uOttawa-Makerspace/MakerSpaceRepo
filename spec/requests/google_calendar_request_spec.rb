# frozen_string_literal: true

require "rails_helper"

# Characterization spec for GoogleCalendarController#webhook (firewall-less
# POST /google/calendar/webhook). Pins the header-driven contract:
#   X-Goog-Resource-State == "sync"  → 200 (no auth, no enqueue)
#   unknown channel/resource pair    → 401
#   live channel row with its token  → 200 + enqueues GoogleCalendarSyncJob

RSpec.describe "Google calendar webhook", type: :request do
  let(:webhook_path) { "/google/calendar/webhook" }

  def post_webhook(headers)
    token = GoogleCalendarChannel.token_for(headers["X-Goog-Channel-Id"])
    post webhook_path, headers: { "X-Goog-Channel-Token" => token }.merge(headers)
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

  it "refuses an EXPIRED channel pair and enqueues nothing" do
    GoogleCalendarChannel.create!(
      channel_id: "chan-old", resource_id: "res-old",
      expires_at: 1.week.ago
    )

    post_webhook({
      "X-Goog-Channel-Id" => "chan-old",
      "X-Goog-Resource-Id" => "res-old",
      "X-Goog-Resource-State" => "exists"
    })

    expect(response.status).to eq(401)
    expect(GoogleCalendarSyncJob).not_to have_been_enqueued
  end

  describe "the channel token" do
    let(:ids) { { "X-Goog-Channel-Id" => "chan-t", "X-Goog-Resource-Id" => "res-t", "X-Goog-Resource-State" => "exists" } }

    before { GoogleCalendarChannel.create!(channel_id: "chan-t", resource_id: "res-t", expires_at: 1.week.from_now) }

    it "401s without the token header (a channel registered before tokens were sent)" do
      post webhook_path, headers: ids
      expect(response.status).to eq(401)
      expect(GoogleCalendarSyncJob).not_to have_been_enqueued
    end

    it "401s with a wrong token, or another channel's token" do
      post webhook_path, headers: ids.merge("X-Goog-Channel-Token" => "nope")
      expect(response.status).to eq(401)
      post webhook_path, headers: ids.merge("X-Goog-Channel-Token" => GoogleCalendarChannel.token_for("chan-other"))
      expect(response.status).to eq(401)
      expect(GoogleCalendarSyncJob).not_to have_been_enqueued
    end

    it "accepts the channel's own token" do
      expect { post webhook_path, headers: ids.merge("X-Goog-Channel-Token" => GoogleCalendarChannel.token_for("chan-t")) }
        .to have_enqueued_job(GoogleCalendarSyncJob)
      expect(response.status).to eq(200)
    end
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
