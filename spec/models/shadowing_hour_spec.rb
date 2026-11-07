require "rails_helper"

RSpec.describe ShadowingHour, type: :model do
  it { should belong_to(:user).without_validating_presence }
  it { should belong_to(:space).without_validating_presence }

  describe "times" do
    let(:start_time) { Time.zone.parse("2030-01-07 10:00") }

    it "are both required on a new row" do
      expect(ShadowingHour.new(end_time: start_time)).not_to be_valid
      expect(ShadowingHour.new(start_time: start_time)).not_to be_valid
      expect(ShadowingHour.new(start_time: start_time, end_time: start_time + 1.hour)).to be_valid
    end

    it "keep a stored row without times editable for its other fields" do
      shift = create(:shadowing_hour)
      shift.update_columns(start_time: nil, end_time: nil)

      expect(shift.reload.update(event_id: "evt-1")).to be(true)
    end

    it "cannot be cleared on a stored row" do
      expect(create(:shadowing_hour).update(end_time: nil)).to be(false)
    end

    it "are both needed once either one is changed on a row that has none" do
      shift = create(:shadowing_hour)
      shift.update_columns(start_time: nil, end_time: nil)

      expect(shift.reload.update(start_time: start_time)).to be(false)
      expect(shift.update(start_time: start_time, end_time: start_time + 1.hour)).to be(true)
    end
  end

  it "lists only rows that have both times as complete" do
    whole = create(:shadowing_hour)
    create(:shadowing_hour).update_column(:end_time, nil)
    create(:shadowing_hour).update_column(:start_time, nil)

    expect(ShadowingHour.complete).to contain_exactly(whole)
  end

  # Chunk 13: Google Calendar is faked at the service boundary.
  describe "calendar calls" do
    let(:service) { instance_double(Google::Apis::CalendarV3::CalendarService, :authorization= => nil) }
    let(:user) { create(:user, :volunteer_with_volunteer_program, name: "Vera") }
    let(:calendars) { Rails.application.credentials[:test][:calendar] }

    before do
      allow(ShadowingHour).to receive(:authorizer).and_return(double("auth"))
      allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service)
    end

    describe ".create_event" do
      it "inserts a '<name> Shadowing' event in the makerspace calendar with no attendees under test" do
        expect(service).to receive(:insert_event) do |calendar_id, event, opts|
          expect(calendar_id).to eq(calendars[:makerspace])
          expect(event.summary).to eq("Vera Shadowing")
          expect(event.attendees).to eq([])
          expect(event.start.time_zone).to eq("America/Toronto")
          expect(event.start.date_time.to_s).to include("2030-05-06")
          expect(opts).to eq(send_notifications: true)
          :response
        end
        expect(ShadowingHour.create_event("2030-05-06T 9:00:00", "2030-05-06T11:00:00", user, "makerspace")).to eq(:response)
      end

      it "uses the brunsfield calendar for any other space string" do
        expect(service).to receive(:insert_event).with(calendars[:brunsfield], anything, anything)
        ShadowingHour.create_event("2030-05-06T09:00:00", "2030-05-06T11:00:00", user, "brunsfield centre")
      end
    end

    describe ".delete_event" do
      it "uses the makerspace calendar only for the exact name 'Makerspace' (case-sensitive)" do
        expect(service).to receive(:delete_event).with(calendars[:makerspace], "e1").and_return(:ok)
        expect(ShadowingHour.delete_event("e1", "Makerspace")).to eq(:ok)
        expect(service).to receive(:delete_event).with(calendars[:brunsfield], "e2").and_return(:ok)
        ShadowingHour.delete_event("e2", "makerspace")
      end

      it "treats an already-deleted event as success (returns nil)" do
        allow(service).to receive(:delete_event).and_raise(Google::Apis::ClientError.new("Resource has been deleted"))
        expect(ShadowingHour.delete_event("e1", "Makerspace")).to be_nil
      end

      it "returns 'error' for other client errors and for any other exception" do
        allow(service).to receive(:delete_event).and_raise(Google::Apis::ClientError.new("notFound"))
        expect(ShadowingHour.delete_event("e1", "Makerspace")).to eq("error")
        allow(service).to receive(:delete_event).and_raise(StandardError, "boom")
        expect(ShadowingHour.delete_event("e1", "Makerspace")).to eq("error")
      end
    end
  end
end
