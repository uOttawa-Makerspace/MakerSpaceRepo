# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::EventDeleteJob, type: :job do
  let(:service) { instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil) }
  let(:calendar_id) { "c_cal@group.calendar.google.com" }

  before { allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service) }

  def client_error(status) = Google::Apis::ClientError.new("failed", status_code: status)

  it "deletes the Google event" do
    expect(service).to receive(:delete_event).with(calendar_id, "abc123")
    described_class.perform_now("abc123", calendar_id)
  end

  [404, 410].each do |status|
    it "counts a #{status} answer as done" do
      allow(service).to receive(:delete_event).and_raise(client_error(status))
      expect(Rails.error).not_to receive(:report)
      expect { described_class.perform_now("abc123", calendar_id) }.not_to have_enqueued_job(described_class)
    end
  end

  it "reports any other client error and does not retry it" do
    allow(service).to receive(:delete_event).and_raise(client_error(403))
    expect(Rails.error).to receive(:report)
      .with(instance_of(Google::Apis::ClientError), hash_including(context: hash_including(google_event_id: "abc123")))
    expect { described_class.perform_now("abc123", calendar_id) }.not_to have_enqueued_job(described_class)
  end

  it "retries a server error" do
    allow(service).to receive(:delete_event).and_raise(Google::Apis::ServerError.new("down", status_code: 500))
    expect { described_class.perform_now("abc123", calendar_id) }.to have_enqueued_job(described_class).with("abc123", calendar_id)
  end

  it "retries a failure to fetch the access token" do
    allow(GoogleCalendar::EventPublisher).to receive(:authorizer).and_raise(Signet::RemoteServerError, "down")
    expect { described_class.perform_now("abc123", calendar_id) }.to have_enqueued_job(described_class).with("abc123", calendar_id)
  end

  describe "when the event still exists" do
    let(:test_calendar) { "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com" }
    let(:other_calendar) { "c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com" }

    it "removes the old calendar's copy of an event that now belongs to another calendar" do
      event = create(:event, space: create(:space, name: "MTC"), google_event_id: "abc123")
      expect(service).to receive(:delete_event).with(test_calendar, "abc123")
      described_class.perform_now("abc123", test_calendar, event.id)
    end

    it "keeps the copy when the event has moved back to that calendar under the same id" do
      event = create(:event, space: create(:space), google_event_id: "abc123")
      expect(service).not_to receive(:delete_event)
      described_class.perform_now("abc123", test_calendar, event.id)
    end

    it "removes the copy when the event now has another Google id in that calendar" do
      event = create(:event, space: create(:space), google_event_id: "other")
      expect(service).to receive(:delete_event).with(test_calendar, "abc123")
      described_class.perform_now("abc123", test_calendar, event.id)
    end

    it "removes the copy when the event is gone" do
      expect(service).to receive(:delete_event).with(test_calendar, "abc123")
      described_class.perform_now("abc123", test_calendar, 0)
    end
  end
end
