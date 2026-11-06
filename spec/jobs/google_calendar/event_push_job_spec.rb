# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::EventPushJob, type: :job do
  include ActiveJob::TestHelper

  let(:service) { instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil) }
  let(:space) { create(:space) }
  let(:event) do
    create(:event, space: space, title: "Open Lab", google_event_id: "abc123",
                   start_time: Time.utc(2027, 4, 1, 14), end_time: Time.utc(2027, 4, 1, 15))
  end
  let(:calendar_id) { "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com" }

  before { allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service) }

  def client_error(status) = Google::Apis::ClientError.new("failed", status_code: status)

  it "updates the event under the Google id stored on it" do
    sent = nil
    allow(service).to receive(:update_event) { |cal, id, gcal| sent = [cal, id, gcal] }
    expect(service).not_to receive(:insert_event)

    described_class.perform_now(event.id)

    expect(sent[0..1]).to eq([calendar_id, "abc123"])
    expect(sent.last.summary).to eq("Open Lab")
  end

  it "reads the event when it runs, so the latest state is what is sent" do
    event.update_columns(title: "Renamed")
    sent = nil
    allow(service).to receive(:update_event) { |_cal, _id, gcal| sent = gcal }
    described_class.perform_now(event.id)
    expect(sent.summary).to eq("Renamed")
  end

  it "inserts with the same id when Google does not have the event yet (404)" do
    allow(service).to receive(:update_event).and_raise(client_error(404))
    sent = nil
    allow(service).to receive(:insert_event) { |cal, gcal| sent = [cal, gcal] }

    described_class.perform_now(event.id)

    expect(sent.first).to eq(calendar_id)
    expect(sent.last.id).to eq("abc123")
  end

  it "updates once more when the insert finds the id already there (409)" do
    calls = 0
    allow(service).to receive(:update_event) { calls += 1; raise client_error(404) if calls == 1 }
    allow(service).to receive(:insert_event).and_raise(client_error(409))

    described_class.perform_now(event.id)

    expect(calls).to eq(2)
  end

  it "does nothing for an event that no longer exists" do
    expect(Google::Apis::CalendarV3::CalendarService).not_to receive(:new)
    described_class.perform_now(0)
  end

  it "does nothing for a draft" do
    draft = create(:event, :draft, space: space, google_event_id: nil)
    expect(Google::Apis::CalendarV3::CalendarService).not_to receive(:new)
    described_class.perform_now(draft.id)
  end

  it "retries a Google server error later instead of failing" do
    allow(service).to receive(:update_event).and_raise(Google::Apis::ServerError.new("down", status_code: 503))
    expect(Rails.error).not_to receive(:report)

    expect { described_class.perform_now(event.id) }.to have_enqueued_job(described_class).with(event.id)
  end

  [Google::Apis::RateLimitError.new("slow", status_code: 429), Google::Apis::TransmissionError.new("net"),
   Net::ReadTimeout.new].each do |error|
    it "retries #{error.class}" do
      allow(service).to receive(:update_event).and_raise(error)
      expect { described_class.perform_now(event.id) }.to have_enqueued_job(described_class)
    end
  end

  it "reports a client error other than a conflict and does not retry it" do
    allow(service).to receive(:update_event).and_raise(client_error(400))
    expect(Rails.error).to receive(:report)
      .with(instance_of(Google::Apis::ClientError), hash_including(handled: true, context: hash_including(event_id: event.id)))

    expect { described_class.perform_now(event.id) }.not_to have_enqueued_job(described_class)
  end

  it "reports once the retries run out" do
    attempts = 0
    allow(service).to receive(:update_event) do
      attempts += 1
      raise Google::Apis::ServerError.new("down", status_code: 503)
    end
    expect(Rails.error).to receive(:report).once
      .with(instance_of(Google::Apis::ServerError), hash_including(context: hash_including(event_id: event.id)))

    perform_enqueued_jobs { described_class.perform_later(event.id) }

    expect(attempts).to eq(described_class::ATTEMPTS)
  end

  describe "access token failures" do
    [Signet::AuthorizationError.new("denied"), Signet::RemoteServerError.new("down"), Faraday::ConnectionFailed.new("refused"),
     Faraday::TimeoutError.new("slow"), Faraday::SSLError.new("ssl"), SocketError.new("dns"),
     OpenSSL::SSL::SSLError.new("ssl"), Errno::ECONNRESET.new].each do |error|
      it "retries #{error.class} raised while fetching the token" do
        allow(GoogleCalendar::EventPublisher).to receive(:authorizer).and_raise(error)
        expect(Rails.error).not_to receive(:report)
        expect { described_class.perform_now(event.id) }.to have_enqueued_job(described_class).with(event.id)
      end
    end

    it "reports once the retries run out" do
      attempts = 0
      allow(GoogleCalendar::EventPublisher).to receive(:authorizer) { attempts += 1; raise Faraday::ConnectionFailed, "refused" }
      expect(Rails.error).to receive(:report).once
        .with(instance_of(Faraday::ConnectionFailed), hash_including(context: hash_including(event_id: event.id)))

      perform_enqueued_jobs { described_class.perform_later(event.id) }

      expect(attempts).to eq(described_class::ATTEMPTS)
    end
  end

  describe "insert after a 404" do
    it "reports an insert refused with any status other than a conflict" do
      allow(service).to receive(:update_event).and_raise(client_error(404))
      allow(service).to receive(:insert_event).and_raise(client_error(403))
      expect(Rails.error).to receive(:report).with(instance_of(Google::Apis::ClientError), anything)

      described_class.perform_now(event.id)
    end
  end

  describe "the Google client" do
    it "signs in with the service account of the credentials" do
      google = { private_key: "k", client_email: "e", project_id: "p", private_key_id: "i", type: "service_account", extra: "x" }
      allow(Rails.application.credentials).to receive(:[]).with(Rails.env.to_sym).and_return({ google: google })
      allow(GoogleCalendar::EventPublisher).to receive(:authorizer).and_call_original
      creds = instance_double(Google::Auth::ServiceAccountCredentials, "sub=": nil, fetch_access_token!: true)
      captured = nil
      allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds) { |args| captured = args; creds }

      expect(GoogleCalendar::EventPublisher.authorizer).to eq(creds)
      expect(JSON.parse(captured[:json_key_io].read).keys).to match_array(%w[private_key client_email project_id private_key_id type])
      expect(creds).to have_received(:sub=).with("volunteer@makerepo.com")
    end
  end

  describe "calendars" do
    let(:shop) { create(:space, name: "Makerspace") }
    let(:mtc) { create(:space, name: "MTC") }
    let(:shop_calendar) { "c_g1bk6ctpenjeko2dourrr0h6pc@group.calendar.google.com" }
    let(:mtc_calendar) { "c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com" }
    # Google as a set of [calendar, id] pairs. A move into a calendar that already has the id is refused (409).
    let(:google) { Set.new }

    before do
      allow(service).to receive(:update_event) do |cal, id, _|
        raise client_error(404) unless google.include?([cal, id])
      end
      allow(service).to receive(:insert_event) do |cal, gcal|
        raise client_error(409) if google.include?([cal, gcal.id])

        google << [cal, gcal.id]
      end
      allow(service).to receive(:move_event) do |from, id, to|
        raise client_error(404) unless google.include?([from, id])
        raise client_error(409) if google.include?([to, id])

        google.delete([from, id])
        google << [to, id]
      end
    end

    it "records the calendar after the first insert and leaves it alone on later pushes" do
      event.update_columns(space_id: shop.id)
      described_class.perform_now(event.id)
      expect(event.reload.google_calendar_id).to eq(shop_calendar)
      expect(google).to eq(Set[[shop_calendar, "abc123"]])

      expect(service).not_to receive(:move_event)
      described_class.perform_now(event.id)
    end

    it "treats an empty record as today: updates in the calendar of the space, then records it" do
      event.update_columns(space_id: shop.id)
      google << [shop_calendar, "abc123"]
      expect(service).not_to receive(:insert_event)

      described_class.perform_now(event.id)

      expect(event.reload.google_calendar_id).to eq(shop_calendar)
    end

    it "moves the copy from the recorded calendar to the one of the space, then updates it" do
      event.update_columns(space_id: mtc.id, google_calendar_id: shop_calendar)
      google << [shop_calendar, "abc123"]

      described_class.perform_now(event.id)

      expect(google).to eq(Set[[mtc_calendar, "abc123"]])
      expect(event.reload.google_calendar_id).to eq(mtc_calendar)
    end

    it "converges on one copy when the pushes of two successive moves run in either order" do
      event.update_columns(space_id: shop.id)
      described_class.perform_now(event.id) # inserted in the shop
      event.update_columns(space_id: mtc.id) # moved to MTC, then on to the test calendar before any job ran
      event.update_columns(space_id: space.id)

      2.times { described_class.perform_now(event.id) }

      expect(google).to eq(Set[[calendar_id, "abc123"]])
      expect(event.reload.google_calendar_id).to eq(calendar_id)
    end

    it "moves back and forth without leaving a copy behind" do
      event.update_columns(space_id: shop.id)
      described_class.perform_now(event.id)
      event.update_columns(space_id: mtc.id)
      described_class.perform_now(event.id)
      event.update_columns(space_id: shop.id)
      described_class.perform_now(event.id)

      expect(google).to eq(Set[[shop_calendar, "abc123"]])
    end

    it "inserts when the recorded calendar does not have the event (404 on the move)" do
      event.update_columns(space_id: mtc.id, google_calendar_id: shop_calendar)

      described_class.perform_now(event.id)

      expect(google).to eq(Set[[mtc_calendar, "abc123"]])
      expect(event.reload.google_calendar_id).to eq(mtc_calendar)
    end

    it "reports a move that is refused for good and keeps the recorded calendar, so the next push moves instead of inserting" do
      event.update_columns(space_id: mtc.id, google_calendar_id: shop_calendar)
      google << [shop_calendar, "abc123"]
      refuse = true
      allow(service).to receive(:move_event) do |from, id, to|
        raise client_error(403) if refuse

        google.delete([from, id])
        google << [to, id]
      end
      expect(Rails.error).to receive(:report).with(instance_of(Google::Apis::ClientError), anything)

      described_class.perform_now(event.id)

      expect(event.reload.google_calendar_id).to eq(shop_calendar)
      expect(google).to eq(Set[[shop_calendar, "abc123"]])

      refuse = false
      described_class.perform_now(event.id)
      expect(google).to eq(Set[[mtc_calendar, "abc123"]])
    end
  end
end
