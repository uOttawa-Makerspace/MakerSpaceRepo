# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::EventDeleteJob, type: :job do
  let(:service) { instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil) }
  let(:calendar_id) { "c_cal@group.calendar.google.com" }

  before { allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service) }

  def client_error(status) = Google::Apis::ClientError.new("failed", status_code: status)

  it "deletes the Google event" do
    expect(service).to receive(:delete_event).with(calendar_id, "abc123")
    described_class.perform_now("abc123", calendar_id, 7)
  end

  [404, 410].each do |status|
    it "counts a #{status} answer as done" do
      allow(service).to receive(:delete_event).and_raise(client_error(status))
      expect(Rails.error).not_to receive(:report)
      expect { described_class.perform_now("abc123", calendar_id, 7) }.not_to have_enqueued_job(described_class)
    end
  end

  it "reports any other client error and does not retry it" do
    allow(service).to receive(:delete_event).and_raise(client_error(403))
    expect(Rails.error).to receive(:report)
      .with(instance_of(Google::Apis::ClientError), hash_including(context: hash_including(google_event_id: "abc123")))
    expect { described_class.perform_now("abc123", calendar_id, 7) }.not_to have_enqueued_job(described_class)
  end

  it "retries a server error" do
    allow(service).to receive(:delete_event).and_raise(Google::Apis::ServerError.new("down", status_code: 500))
    expect { described_class.perform_now("abc123", calendar_id, 7) }.to have_enqueued_job(described_class).with("abc123", calendar_id, 7)
  end

  it "retries a failure to fetch the access token" do
    allow(GoogleCalendar::EventPublisher).to receive(:authorizer).and_raise(Signet::RemoteServerError, "down")
    expect { described_class.perform_now("abc123", calendar_id, 7) }.to have_enqueued_job(described_class).with("abc123", calendar_id, 7)
  end
end
