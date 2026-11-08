# frozen_string_literal: true

require "rails_helper"

# Chunk 18 (carried over from chunk 11): GoogleCalendarSyncJob. Google is
# stubbed at the HTTP boundary (WebMock on the Calendar v3 events.list URL); only
# the service-account authorizer (credentials + token fetch) is replaced by a
# minimal object that signs requests. The job and GoogleCalendar::EventProcessor
# run for real.
RSpec.describe GoogleCalendarSyncJob, type: :job do
  include Chunk18GoogleHelpers

  EVENTS_URL = "https://www.googleapis.com/calendar/v3/calendars/primary/events"

  let(:authorizer) do
    Class.new { def apply!(headers) = headers["Authorization"] = "Bearer test-token" }.new
  end
  let!(:approved) { create(:booking_status, :approved) }
  let!(:space) { create(:space) }
  let!(:stm124) { create(:sub_space, name: "STM 124", space: space) }
  let!(:creator) { create(:user, :regular_user, email: "creator@example.test") }

  before do
    allow(SubSpaceBooking).to receive(:authorizer).and_return(authorizer)
  end

  def stub_events(events_or_status, **json_opts)
    response =
      if events_or_status.is_a?(Integer)
        { status: events_or_status, body: { error: { code: events_or_status, message: "nope" } }.to_json,
          headers: { "Content-Type" => "application/json" } }
      else
        { status: 200, body: c18_gcal_events_json(events_or_status, **json_opts),
          headers: { "Content-Type" => "application/json" } }
      end
    stub_request(:get, EVENTS_URL).with(query: hash_including({})).to_return(response)
  end

  def channel(**attrs)
    GoogleCalendarChannel.create!({ channel_id: "c1", resource_id: "r1", expires_at: 1.week.from_now }.merge(attrs))
  end

  it "is queued on the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  describe "request shape" do
    it "without a channel does a full listing (showDeleted + singleEvents, no syncToken, primary calendar)" do
      stub_events([], next_sync_token: "T1")
      described_class.perform_now
      expect(a_request(:get, EVENTS_URL).with(
        query: { "showDeleted" => "true", "singleEvents" => "true" },
        headers: { "Authorization" => "Bearer test-token" }
      )).to have_been_made.once
    end

    it "uses the sync token of the active channel that expires last" do
      channel(channel_id: "soon", resource_id: "r1", expires_at: 1.day.from_now, sync_token: "SOON")
      channel(channel_id: "late", resource_id: "r2", expires_at: 5.days.from_now, sync_token: "LATE")
      channel(channel_id: "gone", resource_id: "r3", expires_at: 1.day.ago, sync_token: "EXPIRED")
      stub_events([], next_sync_token: "T2")
      described_class.perform_now
      expect(a_request(:get, EVENTS_URL).with(
        query: { "syncToken" => "LATE", "showDeleted" => "true", "singleEvents" => "true" }
      )).to have_been_made.once
    end

    it "ignores expired channels (full listing when only expired channels exist)" do
      channel(expires_at: 1.day.ago, sync_token: "EXPIRED")
      stub_events([])
      described_class.perform_now
      expect(a_request(:get, EVENTS_URL).with(query: { "showDeleted" => "true", "singleEvents" => "true" }))
        .to have_been_made.once
    end
  end

  describe "processing" do
    it "feeds every returned event through EventProcessor and stores the next sync token on the channel" do
      chan = channel(sync_token: "OLD")
      stub_events([c18_gcal_event(id: "e1"), c18_gcal_event(id: "e2", location: "Elsewhere")], next_sync_token: "NEW")
      expect { described_class.perform_now }.to change(SubSpaceBooking, :count).by(1)
      expect(SubSpaceBooking.find_by(google_booking_id: "e1")).to be_present
      expect(chan.reload.sync_token).to eq("NEW")
    end

    it "without a channel the next sync token is dropped (nowhere to store it)" do
      stub_events([c18_gcal_event], next_sync_token: "NEW")
      expect { described_class.perform_now }.to change(SubSpaceBooking, :count).by(1)
      expect(GoogleCalendarChannel.count).to eq(0)
    end

    it "keeps the old token when the response carries no nextSyncToken" do
      chan = channel(sync_token: "OLD")
      stub_events([])
      described_class.perform_now
      expect(chan.reload.sync_token).to eq("OLD")
    end

    it "applies cancellations from a later run" do
      stub_events([c18_gcal_event(id: "e1")], next_sync_token: "A")
      described_class.perform_now
      expect(SubSpaceBooking.find_by(google_booking_id: "e1")).to be_present
      stub_events([c18_gcal_event(id: "e1", status: "cancelled")], next_sync_token: "B")
      described_class.perform_now
      expect(SubSpaceBooking.find_by(google_booking_id: "e1")).to be_nil
    end
  end

  describe "pagination" do
    def stub_page(query, events, next_page_token: nil, next_sync_token: nil)
      stub_request(:get, EVENTS_URL).with(query: query).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: c18_gcal_events_json(events, next_page_token: next_page_token, next_sync_token: next_sync_token)
      )
    end

    it "reads every page, processes the events of all of them and stores the token of the last page" do
      chan = channel(sync_token: "OLD")
      base = { "syncToken" => "OLD", "showDeleted" => "true", "singleEvents" => "true" }
      stub_page(base, [c18_gcal_event(id: "page-1")], next_page_token: "PAGE2")
      stub_page(base.merge("pageToken" => "PAGE2"), [c18_gcal_event(id: "page-2")], next_sync_token: "DONE")
      described_class.perform_now
      expect(SubSpaceBooking.where(google_booking_id: %w[page-1 page-2]).count).to eq(2)
      expect(chan.reload.sync_token).to eq("DONE")
    end
  end

  describe "ClientError handling" do
    def gone(query)
      stub_request(:get, EVENTS_URL).with(query: query)
        .to_return(status: 410, body: { error: { code: 410, message: "Gone" } }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    it "clears the channel's sync token and lists the whole calendar once (a 410 'sync token expired' recovers)" do
      chan = channel(sync_token: "STALE")
      gone("syncToken" => "STALE", "showDeleted" => "true", "singleEvents" => "true")
      stub_request(:get, EVENTS_URL).with(query: { "showDeleted" => "true", "singleEvents" => "true" })
        .to_return(status: 200, body: c18_gcal_events_json([c18_gcal_event(id: "fresh")], next_sync_token: "FRESH"),
                   headers: { "Content-Type" => "application/json" })
      described_class.perform_now
      expect(SubSpaceBooking.find_by(google_booking_id: "fresh")).to be_present
      expect(chan.reload.sync_token).to eq("FRESH")
    end

    it "gives up when the full listing is refused too: two requests, then the error is raised" do
      channel(sync_token: "STALE")
      gone(hash_including({}))
      expect { described_class.perform_now }.to raise_error(Google::Apis::ClientError)
      expect(a_request(:get, EVENTS_URL).with(query: hash_including({}))).to have_been_made.twice
    end

    it "raises a permanent client error (403) at once, with one request and the sync token kept" do
      chan = channel(sync_token: "S")
      stub_events(403)
      expect { described_class.perform_now }.to raise_error(Google::Apis::ClientError)
      expect(a_request(:get, EVENTS_URL).with(query: hash_including({}))).to have_been_made.once
      expect(chan.reload.sync_token).to eq("S")
    end

    it "does not rescue server errors (5xx propagate to the queue's retry policy)" do
      stub_events(503)
      expect { described_class.perform_now }.to raise_error(Google::Apis::ServerError)
    end
  end

  describe "bad events (EventProcessor failures)" do
    it "reports the one event that raises and carries on with the rest, storing the new sync token" do
      chan = channel(sync_token: "OLD")
      events = [c18_gcal_event(id: "good-1"),
                c18_gcal_event(id: "bad", start_at: Time.utc(2027, 4, 5, 16), end_at: Time.utc(2027, 4, 5, 15)),
                c18_gcal_event(id: "good-2")]
      stub_events(events, next_sync_token: "NEW")
      expect(Rails.error).to receive(:report)
        .with(instance_of(ActiveRecord::RecordInvalid), hash_including(handled: true, context: hash_including(google_event_id: "bad"))).once
      expect { described_class.perform_now }.not_to raise_error
      expect(SubSpaceBooking.where(google_booking_id: %w[good-1 good-2]).count).to eq(2)
      expect(chan.reload.sync_token).to eq("NEW")
    end

    [ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::ConnectionNotEstablished].each do |error|
      it "fails the job on a transient database error (#{error}) and does not advance the sync token" do
        chan = channel(sync_token: "OLD")
        stub_events([c18_gcal_event(id: "e1")], next_sync_token: "NEW")
        allow(GoogleCalendar::EventProcessor).to receive(:process).and_raise(error, "db")
        expect(Rails.error).not_to receive(:report)
        expect { described_class.perform_now }.to raise_error(error)
        expect(chan.reload.sync_token).to eq("OLD")
      end
    end

    it "still reports and skips a data error in a single event" do
      stub_events([c18_gcal_event(id: "e1")], next_sync_token: "NEW")
      allow(GoogleCalendar::EventProcessor).to receive(:process).and_raise(ActiveRecord::RecordInvalid.new(SubSpaceBooking.new))
      expect(Rails.error).to receive(:report).once
      expect { described_class.perform_now }.not_to raise_error
    end
  end
end

RSpec.describe GoogleCalendarSyncJob, "concurrency limit" do
  it "runs one sync at a time" do
    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.new.concurrency_key).to be_present
  end
end
