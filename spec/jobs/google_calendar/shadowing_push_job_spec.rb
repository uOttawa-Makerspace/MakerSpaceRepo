# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::ShadowingPushJob, type: :job do
  include ActiveJob::TestHelper

  let(:service) { instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil) }
  let(:volunteer) { create(:user, :volunteer_with_volunteer_program, name: "Vera") }
  let(:shift) { create(:shadowing_hour, user: volunteer, space: create(:space, name: "Makerspace"), event_id: "abc123") }

  before do
    allow(ShadowingHour).to receive(:authorizer).and_return(double("auth"))
    allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service)
  end

  def server_error = Google::Apis::ServerError.new("down", status_code: 500)

  it "creates the event under the shift's id and settles the pending change" do
    GoogleCalendar::PendingChange.ask_shadow_push(shift.id)
    ids = []
    allow(service).to receive(:insert_event) { |_cal, event, _opts| ids << event.id; double(status: "confirmed") }

    described_class.perform_now(shift.id)

    expect(ids).to eq(["abc123"])
    expect(GoogleCalendar::PendingChange.count).to eq(0)
  end

  it "keeps the pending change when Google fails, and a later run creates the event once under the same id" do
    GoogleCalendar::PendingChange.ask_shadow_push(shift.id)
    allow(service).to receive(:insert_event).and_raise(server_error)
    expect(Rails.error).to receive(:report).with(instance_of(Google::Apis::ServerError), hash_including(handled: true)).at_least(:once)
    perform_enqueued_jobs { described_class.perform_later(shift.id) }
    expect(GoogleCalendar::PendingChange.count).to eq(1)

    ids = []
    allow(service).to receive(:insert_event) { |_cal, event, _opts| ids << event.id; double(status: "confirmed") }
    described_class.perform_now(shift.id)

    expect(ids).to eq(["abc123"])
    expect(GoogleCalendar::PendingChange.count).to eq(0)
  end

  it "settles when Google already has the event, so a repeat never makes a second one" do
    GoogleCalendar::PendingChange.ask_shadow_push(shift.id)
    allow(service).to receive(:insert_event).and_raise(Google::Apis::ClientError.new("duplicate", status_code: 409))
    described_class.perform_now(shift.id)
    expect(GoogleCalendar::PendingChange.count).to eq(0)
  end

  it "reports a refusal and leaves the change for the resend job" do
    GoogleCalendar::PendingChange.ask_shadow_push(shift.id)
    allow(service).to receive(:insert_event).and_raise(Google::Apis::ClientError.new("refused", status_code: 403))
    expect(Rails.error).to receive(:report).with(instance_of(Google::Apis::ClientError), hash_including(handled: true, context: hash_including(shadowing_hour_id: shift.id)))
    described_class.perform_now(shift.id)
    expect(GoogleCalendar::PendingChange.count).to eq(1)
  end

  it "settles without calling Google when the shift is gone" do
    GoogleCalendar::PendingChange.ask_shadow_push(shift.id)
    GoogleCalendar::PendingChange.update_all(shadowing_hour_id: shift.id) # still waiting
    ShadowingHour.where(id: shift.id).delete_all
    expect(service).not_to receive(:insert_event)
    described_class.perform_now(shift.id)
    expect(GoogleCalendar::PendingChange.count).to eq(0)
  end

  it "ends in a report once the transient attempts run out, leaving the change for the resend job" do
    GoogleCalendar::PendingChange.ask_shadow_push(shift.id)
    allow(service).to receive(:insert_event).and_raise(server_error)
    expect(Rails.error).to receive(:report).with(instance_of(Google::Apis::ServerError), hash_including(context: hash_including(shadowing_hour_id: shift.id)))
    perform_enqueued_jobs(only: described_class) { described_class.perform_later(shift.id) }
    expect(GoogleCalendar::PendingChange.count).to eq(1)
  end
end
