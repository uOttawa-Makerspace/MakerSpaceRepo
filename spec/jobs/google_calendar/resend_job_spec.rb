# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::ResendJob, type: :job do
  it "queues the push and the removal that were never confirmed, and nothing recent" do
    GoogleCalendar::PendingChange.ask_push(7).update_columns(updated_at: 1.hour.ago)
    GoogleCalendar::PendingChange.ask_removal(8, "aaa", "cal").update_columns(updated_at: 1.hour.ago)
    GoogleCalendar::PendingChange.ask_push(9)
    expect { described_class.perform_now }
      .to have_enqueued_job(GoogleCalendar::EventPushJob).with(7).exactly(:once)
      .and have_enqueued_job(GoogleCalendar::EventDeleteJob).with("aaa", "cal", 8).exactly(:once)
    expect(GoogleCalendar::EventPushJob).not_to have_been_enqueued.with(9)
  end

  it "queues the missed push of an event, which the push job then sends and settles" do
    service = instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil, update_event: nil)
    allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service)
    allow(GoogleCalendar::EventPublisher).to receive(:authorizer)
    event = create(:event, draft: false, google_event_id: "abc123")
    allow(GoogleCalendar::EventPushJob).to receive(:perform_later).and_raise(ActiveRecord::ConnectionNotEstablished)
    event.push_to_google_later
    GoogleCalendar::PendingChange.update_all(updated_at: 1.hour.ago)
    allow(GoogleCalendar::EventPushJob).to receive(:perform_later).and_call_original

    perform_enqueued_jobs { described_class.perform_now }

    expect(service).to have_received(:update_event).once
    expect(GoogleCalendar::PendingChange.count).to eq(0)
  end

  it "queues the missed creation of a shadowing shift's event, which the job then sends once and settles" do
    service = instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil)
    allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service)
    allow(ShadowingHour).to receive(:authorizer)
    shift = create(:shadowing_hour, user: create(:user, :volunteer_with_volunteer_program), space: create(:space, name: "Makerspace"), event_id: "abc123")
    allow(GoogleCalendar::ShadowingPushJob).to receive(:perform_later).and_raise(ActiveRecord::ConnectionNotEstablished)
    GoogleCalendar::PendingChange.ask_shadow_push(shift.id).enqueue
    GoogleCalendar::PendingChange.update_all(updated_at: 1.hour.ago)
    allow(GoogleCalendar::ShadowingPushJob).to receive(:perform_later).and_call_original
    allow(service).to receive(:insert_event).and_return(double(status: "confirmed"))

    perform_enqueued_jobs { described_class.perform_now }

    expect(service).to have_received(:insert_event).once
    expect(GoogleCalendar::PendingChange.count).to eq(0)
  end
end
