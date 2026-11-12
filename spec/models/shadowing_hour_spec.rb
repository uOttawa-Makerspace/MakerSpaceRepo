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

      it "creates the event with the id it is given, so a repeat cannot create a second event" do
        expect(service).to receive(:insert_event) { |_calendar_id, event, _opts| expect(event.id).to eq("abc123"); :response }
        ShadowingHour.create_event("2030-05-06T09:00:00", "2030-05-06T11:00:00", user, "makerspace", "abc123")
      end

      it "uses the brunsfield calendar for any other space string" do
        expect(service).to receive(:insert_event).with(calendars[:brunsfield], anything, anything)
        ShadowingHour.create_event("2030-05-06T09:00:00", "2030-05-06T11:00:00", user, "brunsfield centre")
      end
    end

    describe "#publish_to_calendar" do
      let(:space) { create(:space, name: "Makerspace") }
      let(:shift) do
        create(:shadowing_hour, user: user, space: space, event_id: "abc123",
                                start_time: Time.zone.parse("2030-05-06 09:00"), end_time: Time.zone.parse("2030-05-06 11:30"))
      end

      it "inserts the event under the shift's id, at its Eastern wall time, in the calendar of its space" do
        sent = nil
        allow(service).to receive(:insert_event) { |calendar_id, event, _opts| sent = [calendar_id, event]; double(status: "confirmed") }
        shift.publish_to_calendar
        expect(sent[0]).to eq(calendars[:makerspace])
        expect(sent[1].id).to eq("abc123")
        expect(sent[1].summary).to eq("Vera Shadowing")
        expect(sent[1].start.date_time.to_s).to eq("2030-05-06T09:00:00")
        expect(sent[1].end.date_time.to_s).to eq("2030-05-06T11:30:00")
      end

      it "uses the other calendar for another space" do
        shift.update!(space: create(:space, name: "Brunsfield Centre"))
        expect(service).to receive(:insert_event).with(calendars[:brunsfield], anything, anything).and_return(double(status: "confirmed"))
        shift.publish_to_calendar
      end

      it "counts an event Google already has under that id (409) as created" do
        allow(service).to receive(:insert_event).and_raise(Google::Apis::ClientError.new("duplicate", status_code: 409))
        expect { shift.publish_to_calendar }.not_to raise_error
      end

      it "raises any other refusal or failure, for the job to retry" do
        allow(service).to receive(:insert_event).and_raise(Google::Apis::ClientError.new("refused", status_code: 403))
        expect { shift.publish_to_calendar }.to raise_error(Google::Apis::ClientError)
        allow(service).to receive(:insert_event).and_raise(Faraday::ConnectionFailed, "down")
        expect { shift.publish_to_calendar }.to raise_error(Faraday::ConnectionFailed)
      end

      it "reports an event Google answers cancelled, without raising" do
        allow(service).to receive(:insert_event).and_return(double(status: "cancelled"))
        expect(HandledError).to receive(:report).with(instance_of(RuntimeError), hash_including(shadowing_hour_id: shift.id))
        shift.publish_to_calendar
      end

      it "does nothing for a row without a volunteer, space or times" do
        expect(service).not_to receive(:insert_event)
        create(:shadowing_hour, user: nil, space: space).publish_to_calendar
        shift.update_columns(space_id: nil)
        shift.reload.publish_to_calendar
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

      it "reports a failed delete (and not an already-deleted event)" do
        expect(Rails.error).to receive(:report)
          .with(instance_of(Google::Apis::ClientError), hash_including(handled: true, context: hash_including(event_id: "e1")))
        allow(service).to receive(:delete_event).and_raise(Google::Apis::ClientError.new("notFound"))
        ShadowingHour.delete_event("e1", "Makerspace")

        expect(Rails.error).to receive(:report).with(instance_of(Faraday::ConnectionFailed), hash_including(handled: true))
        allow(service).to receive(:delete_event).and_raise(Faraday::ConnectionFailed, "down")
        ShadowingHour.delete_event("e1", "Makerspace")
      end

      it "counts an event Google answers 404 or 410 for as already removed, without a report" do
        expect(Rails.error).not_to receive(:report)
        [404, 410].each do |status|
          allow(service).to receive(:delete_event).and_raise(Google::Apis::ClientError.new("gone", status_code: status))
          expect(ShadowingHour.delete_event("e1", "Makerspace")).to be_nil
        end
      end

      it "does not report an already-deleted event" do
        expect(Rails.error).not_to receive(:report)
        allow(service).to receive(:delete_event).and_raise(Google::Apis::ClientError.new("Resource has been deleted"))
        ShadowingHour.delete_event("e1", "Makerspace")
      end
    end
  end
end
