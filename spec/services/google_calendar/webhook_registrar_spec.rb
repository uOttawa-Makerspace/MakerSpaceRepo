# frozen_string_literal: true

require "rails_helper"

# Chunk 18 (carried over from chunk 11): GoogleCalendar::WebhookRegistrar and
# RenewGoogleCalendarWebhooksJob. Google is stubbed at the HTTP boundary
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
      # the webhook address depends on Rails.env (makerepo.com in production, staging.makerepo.com otherwise); there is no configurable base URL
      expect(described_class.webhook_url).to eq("https://staging.makerepo.com/google/calendar/webhook")
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(described_class.webhook_url).to eq("https://makerepo.com/google/calendar/webhook")
    end

    it "sends no verification token (the receiving webhook checks the channel and resource ids)" do
      # the channel is created without a `token`; GoogleCalendarController#webhook checks the channel_id and resource_id headers
      stub_watch
      described_class.register!
      expect(a_request(:post, WATCH_URL).with { |req| JSON.parse(req.body).key?("token") }).not_to have_been_made
    end

    describe "the channel it replaces" do
      STOP_URL = "https://www.googleapis.com/calendar/v3/channels/stop"

      def old_channel(id, expires_at: 3.days.from_now, sync_token: nil)
        GoogleCalendarChannel.create!(channel_id: id, resource_id: "res-#{id}", expires_at: expires_at, sync_token: sync_token)
      end

      def stub_stop(status: 204)
        stub_request(:post, STOP_URL).to_return(status: status, body: status == 204 ? "" : { error: { code: status } }.to_json,
                                                headers: { "Content-Type" => "application/json" })
      end

      it "stops a live older channel at Google and removes its row, leaving only the new one" do
        old_channel("week-1")
        stub_watch(id: "week-2")
        stub_stop
        described_class.register!
        expect(a_request(:post, STOP_URL).with { |r| JSON.parse(r.body).values_at("id", "resourceId") == %w[week-1 res-week-1] })
          .to have_been_made.once
        expect(GoogleCalendarChannel.pluck(:channel_id)).to eq(["week-2"])
      end

      it "drops an expired channel without calling Google" do
        old_channel("gone", expires_at: 1.day.ago)
        stub_watch(id: "fresh")
        described_class.register!
        expect(a_request(:post, STOP_URL)).not_to have_been_made
        expect(GoogleCalendarChannel.pluck(:channel_id)).to eq(["fresh"])
      end

      it "forgets a channel Google no longer knows (404 on stop)" do
        old_channel("unknown")
        stub_watch(id: "fresh")
        stub_stop(status: 404)
        described_class.register!
        expect(GoogleCalendarChannel.pluck(:channel_id)).to eq(["fresh"])
      end

      it "keeps the old row, reports, and still registers the new channel when Google's stop call fails with a server error" do
        old_channel("stuck")
        stub_watch(id: "fresh")
        stub_stop(status: 503)
        expect(Rails.error).to receive(:report).once
        expect { described_class.register! }.not_to raise_error
        expect(GoogleCalendarChannel.pluck(:channel_id)).to match_array(%w[stuck fresh])
      end

      it "hands the calendar's newest sync token to the new channel" do
        old_channel("older", expires_at: 2.days.from_now, sync_token: "OLDER")
        old_channel("newer", expires_at: 4.days.from_now, sync_token: "NEWER")
        stub_watch(id: "fresh")
        stub_stop
        described_class.register!
        expect(GoogleCalendarChannel.find_by(channel_id: "fresh").sync_token).to eq("NEWER")
      end
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

    it "replaces channels expiring within 2 days (or already expired) by one fresh channel" do
      channel("soon", 1.day.from_now, sync_token: "TOKEN")
      channel("late", 1.hour.ago)
      stub_watch(id: "renewed")
      stub_request(:post, "https://www.googleapis.com/calendar/v3/channels/stop").to_return(status: 204, body: "")
      described_class.perform_now
      expect(WebMock).to have_requested(:post, WATCH_URL).once
      expect(GoogleCalendarChannel.pluck(:channel_id)).to eq(["renewed"])
      expect(GoogleCalendarChannel.find_by(channel_id: "renewed").sync_token).to eq("TOKEN")
    end

    it "a failure while registering keeps the old row" do
      keep = channel("soon", 1.day.from_now)
      stub_request(:post, WATCH_URL).to_return(status: 500, body: "")
      expect { described_class.perform_now }.to raise_error(Google::Apis::ServerError)
      expect(GoogleCalendarChannel.all).to contain_exactly(keep)
    end
  end
end
