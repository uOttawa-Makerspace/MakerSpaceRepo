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
    stub_const("BookingStatus::APPROVED", approved)
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
    it "fetches only the first page: events on later pages are never processed and no sync token is saved" do
      # WART(D-B39): the job ignores nextPageToken (one list_events call, no loop), so with more than one page of events the rest are skipped, and because only the LAST page carries nextSyncToken the stored token is never advanced
      chan = channel(sync_token: "OLD")
      stub_events([c18_gcal_event(id: "page-1")], next_page_token: "PAGE2")
      described_class.perform_now
      expect(a_request(:get, EVENTS_URL).with(query: hash_including({}))).to have_been_made.once
      expect(a_request(:get, EVENTS_URL).with(query: hash_including("pageToken" => "PAGE2"))).not_to have_been_made
      expect(SubSpaceBooking.where(google_booking_id: "page-1").count).to eq(1)
      expect(chan.reload.sync_token).to eq("OLD")
    end
  end

  describe "ClientError handling" do
    it "clears the channel's sync token and retries immediately (a 410 'sync token expired' recovers)" do
      chan = channel(sync_token: "STALE")
      stub_request(:get, EVENTS_URL).with(query: hash_including("syncToken" => "STALE"))
        .to_return(status: 410, body: { error: { code: 410, message: "Gone" } }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, EVENTS_URL).with(query: { "showDeleted" => "true", "singleEvents" => "true" })
        .to_return(status: 200, body: c18_gcal_events_json([c18_gcal_event(id: "fresh")], next_sync_token: "FRESH"),
                   headers: { "Content-Type" => "application/json" })
      described_class.perform_now
      expect(SubSpaceBooking.find_by(google_booking_id: "fresh")).to be_present
      expect(chan.reload.sync_token).to eq("FRESH")
    end

    it "retries forever on any 4xx: it only stops here because the stub finally answers 200" do
      # WART(D-B39): `rescue Google::Apis::ClientError ... retry` has no attempt cap, no backoff and no distinction between a recoverable 410 and a permanent 400/401/403/404; a persistent client error spins the worker (and the Google quota) indefinitely
      channel(sync_token: "S")
      calls = 0
      stub_request(:get, EVENTS_URL).with(query: hash_including({})).to_return do |_request|
        calls += 1
        if calls <= 25
          { status: 403, body: { error: { code: 403, message: "forbidden" } }.to_json,
            headers: { "Content-Type" => "application/json" } }
        else
          { status: 200, body: c18_gcal_events_json([]), headers: { "Content-Type" => "application/json" } }
        end
      end
      expect { described_class.perform_now }.not_to raise_error
      expect(calls).to eq(26)
    end

    it "does not rescue server errors (5xx propagate to the queue's retry policy)" do
      stub_events(503)
      expect { described_class.perform_now }.to raise_error(Google::Apis::ServerError)
    end
  end

  describe "bad events (EventProcessor failures)" do
    it "one event that raises aborts the rest of the batch and the sync token is not saved" do
      # WART(D-B40): EventProcessor.process is called without rescue per event, so a single event that raises (here: no creator) skips every later event in the page and the next sync token is never stored, so the same page is refetched and fails the same way forever
      chan = channel(sync_token: "OLD")
      events = [c18_gcal_event(id: "good-1"),
                c18_gcal_event(id: "bad", creator_email: nil),
                c18_gcal_event(id: "good-2")]
      stub_events(events, next_sync_token: "NEW")
      expect { described_class.perform_now }.to raise_error(NoMethodError)
      expect(SubSpaceBooking.where(google_booking_id: "good-1").count).to eq(1) # processed before the failure, not rolled back
      expect(SubSpaceBooking.where(google_booking_id: "good-2").count).to eq(0)
      expect(chan.reload.sync_token).to eq("OLD")
    end
  end
end
