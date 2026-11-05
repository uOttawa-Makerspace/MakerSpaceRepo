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
end
