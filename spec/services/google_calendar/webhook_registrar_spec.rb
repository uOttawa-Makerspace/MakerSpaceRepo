# frozen_string_literal: true

require "rails_helper"

# Chunk 18 (carried over from chunk 11): GoogleCalendar::WebhookRegistrar and
# RenewGoogleCalendarWebhooksJob (D-B42). Google is stubbed at the HTTP boundary
# (events.watch); the service-account authorizer is replaced by a request signer.
RSpec.describe GoogleCalendar::WebhookRegistrar do
  include Chunk18GoogleHelpers

  WATCH_URL = "https://www.googleapis.com/calendar/v3/calendars/primary/events/watch"

  let(:authorizer) do
    Class.new { def apply!(headers) = headers["Authorization"] = "Bearer test-token" }.new
  end
  let(:expiration_ms) { ((Time.current + 7.days).to_f * 1000).to_i }

  before { allow(SubSpaceBooking).to receive(:authorizer).and_return(authorizer) }

  def stub_watch(id: "google-chan", resource_id: "google-res", expiration: expiration_ms)
    stub_request(:post, WATCH_URL).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { kind: "api#channel", id: id, resourceId: resource_id, expiration: expiration.to_s }.to_json
    )
  end

  describe ".register!" do
    it "POSTs a web_hook channel (random uuid id, staging address outside production) and stores the returned channel" do
      stub_watch
      expect { described_class.register! }.to change(GoogleCalendarChannel, :count).by(1)

      expect(a_request(:post, WATCH_URL).with { |req|
        body = JSON.parse(req.body)
        body["type"] == "web_hook" && body["address"] == "https://staging.makerepo.com/google/calendar/webhook" &&
          body["id"].match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) && !body.key?("token")
      }).to have_been_made.once

      channel = GoogleCalendarChannel.last
      expect(channel).to have_attributes(channel_id: "google-chan", resource_id: "google-res", sync_token: nil)
      expect(channel.expires_at).to be_within(1.second).of(Time.at(expiration_ms / 1000))
    end

    it "registers the production URL only when Rails.env is production, staging for every other env" do
      # WART(D-B42): the webhook address is hard-coded to makerepo.com / staging.makerepo.com by Rails.env, so dev/test/review environments register with the STAGING host (stealing its pushes) and there is no configurable base URL
      expect(described_class.webhook_url).to eq("https://staging.makerepo.com/google/calendar/webhook")
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(described_class.webhook_url).to eq("https://makerepo.com/google/calendar/webhook")
    end

    it "sends no verification token, so the receiving webhook has nothing to check besides the ids" do
      # WART(D-B42): the channel is created without a `token`, and GoogleCalendarController#webhook only checks channel_id/resource_id headers (see D-B41)
      stub_watch
      described_class.register!
      expect(a_request(:post, WATCH_URL).with { |req| JSON.parse(req.body).key?("token") }).not_to have_been_made
    end

    it "adds a row on every call and never prunes older channels (the weekly cron calls register!, nothing schedules the renew job)" do
      # WART(D-B42): config/schedule.rb runs register! every Sunday and RenewGoogleCalendarWebhooksJob is not referenced by the schedule, so expired/duplicate channel rows accumulate and every one stays "valid" for the webhook (D-B41)
      stub_watch(id: "week-1")
      described_class.register!
      stub_watch(id: "week-2")
      described_class.register!
      expect(GoogleCalendarChannel.pluck(:channel_id)).to match_array(%w[week-1 week-2])
    end

    it "raises (and stores nothing) when Google rejects the watch request" do
      stub_request(:post, WATCH_URL).to_return(status: 403, body: { error: { code: 403, message: "no" } }.to_json,
                                                headers: { "Content-Type" => "application/json" })
      expect { described_class.register! }.to raise_error(Google::Apis::ClientError)
      expect(GoogleCalendarChannel.count).to eq(0)
    end

    it "raises RecordInvalid when Google returns a channel id we already store" do
      GoogleCalendarChannel.create!(channel_id: "dup", resource_id: "r", expires_at: 1.week.from_now)
      stub_watch(id: "dup")
      expect { described_class.register! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe RenewGoogleCalendarWebhooksJob do
    def channel(id, expires_at, sync_token: nil)
      GoogleCalendarChannel.create!(channel_id: id, resource_id: "res-#{id}", expires_at: expires_at, sync_token: sync_token)
    end

    it "leaves channels that expire in more than 2 days alone" do
      keep = channel("keep", 3.days.from_now)
      described_class.perform_now
      expect(a_request(:post, WATCH_URL)).not_to have_been_made
      expect(GoogleCalendarChannel.all).to contain_exactly(keep)
    end

    it "replaces a channel expiring within 2 days (or already expired) by a fresh one and drops the old row" do
      channel("soon", 1.day.from_now, sync_token: "TOKEN")
      stub_watch(id: "renewed")
      described_class.perform_now
      expect(GoogleCalendarChannel.pluck(:channel_id)).to eq(["renewed"])
    end

    it "loses the sync token on renewal, so the next sync is a full listing" do
      # WART(D-B42): the new channel starts with sync_token nil and the old row (which held the token) is destroyed, so every renewal forces the next GoogleCalendarSyncJob to re-list and re-process the whole calendar
      channel("soon", 1.day.from_now, sync_token: "TOKEN")
      stub_watch(id: "renewed")
      described_class.perform_now
      expect(GoogleCalendarChannel.find_by(channel_id: "renewed").sync_token).to be_nil
    end

    it "never tells Google to stop the old channel (no channels.stop call)" do
      # WART(D-B42): the old channel is only deleted locally; Google keeps pushing to it until its own expiry, and those pushes hit the webhook as unknown channels (401)
      channel("soon", 1.day.from_now)
      stub_watch(id: "renewed")
      described_class.perform_now
      expect(a_request(:post, "https://www.googleapis.com/calendar/v3/channels/stop")).not_to have_been_made
      expect(WebMock).to have_requested(:post, WATCH_URL).once
    end

    it "registers one new channel PER expiring channel (two stale rows give two registrations)" do
      channel("a", 1.day.from_now)
      channel("b", 1.hour.ago)
      calls = 0
      stub_request(:post, WATCH_URL).to_return do
        calls += 1
        { status: 200, headers: { "Content-Type" => "application/json" },
          body: { id: "new-#{calls}", resourceId: "res-new-#{calls}", expiration: expiration_ms.to_s }.to_json }
      end
      described_class.perform_now
      expect(calls).to eq(2)
      expect(GoogleCalendarChannel.pluck(:channel_id)).to match_array(%w[new-1 new-2])
    end

    it "a failure while registering keeps the old row and aborts the remaining channels" do
      keep = channel("soon", 1.day.from_now)
      stub_request(:post, WATCH_URL).to_return(status: 500, body: "")
      expect { described_class.perform_now }.to raise_error(Google::Apis::ServerError)
      expect(GoogleCalendarChannel.all).to contain_exactly(keep)
    end
  end
end
