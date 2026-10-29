# frozen_string_literal: true

require "rails_helper"

# Chunk 18 (carried over from chunk 11): GoogleCalendar::EventProcessor, the
# per-event half of the Google Calendar -> SubSpaceBooking sync. Events are real
# Google::Apis::CalendarV3::Event objects; there is nothing to stub (no I/O).
RSpec.describe GoogleCalendar::EventProcessor, :booking_clock do
  include Chunk18GoogleHelpers

  let!(:approved) { create(:booking_status, :approved) }
  let!(:space) { create(:space) }
  let!(:stm124) { create(:sub_space, name: "STM 124", space: space) }
  let!(:stm126) { create(:sub_space, name: "STM 126", space: space) }
  let!(:creator) { create(:user, :regular_user, email: "creator@example.test") }

  before { stub_const("BookingStatus::APPROVED", approved) }

  def booking_for(id)
    SubSpaceBooking.find_by(google_booking_id: id)
  end

  describe "location filter" do
    it "ignores events whose location is not exactly 'STM 124' or 'STM 126'" do
      ["STM 125", "stm 124", "", nil, "Room STM 124"].each_with_index do |location, i|
        expect { described_class.process(c18_gcal_event(id: "x#{i}", location: location)) }
          .not_to change(SubSpaceBooking, :count)
      end
    end

    it "strips surrounding whitespace before comparing" do
      described_class.process(c18_gcal_event(location: "  STM 126\n"))
      expect(booking_for("evt-1").sub_space).to eq(stm126)
    end
  end

  describe "upsert (confirmed event)" do
    it "creates an approved, blocking booking owned by the creator's user, with the event's times" do
      described_class.process(c18_gcal_event)
      booking = booking_for("evt-1")
      expect(booking).to have_attributes(
        name: "Team meeting", description: "Weekly", sub_space: stm124, blocking: true, user: creator,
        start_time: Time.utc(2027, 4, 5, 14), end_time: Time.utc(2027, 4, 5, 15)
      )
      expect(booking.sub_space_booking_status.booking_status).to eq(approved)
      expect(booking.sub_space_booking_status_id).to eq(booking.sub_space_booking_status.id)
    end

    # D-B18: the past-date rule is for bookings made in the app. A full sync
    # lists past events too, and the mirror keeps them.
    it "mirrors an event that is already in the past" do
      described_class.process(c18_gcal_event(start_at: 1.week.ago.utc, end_at: 1.week.ago.utc + 1.hour))
      booking = booking_for("evt-1")
      expect(booking).to be_persisted
      expect(booking.sub_space_booking_status.booking_status).to eq(approved)
    end

    it "defaults a blank summary/description to 'Google Calendar Event' / 'No description'" do
      described_class.process(c18_gcal_event(summary: "", description: nil))
      expect(booking_for("evt-1")).to have_attributes(name: "Google Calendar Event", description: "No description")
    end

    it "falls back to the hard-coded avend029@uottawa.ca user when the creator has no account" do
      # WART(D-R24): events from unknown creators are attributed to a hard-coded personal address (avend029@uottawa.ca); if that user does not exist the booking has no owner
      fallback = create(:user, :regular_user, email: "avend029@uottawa.ca")
      described_class.process(c18_gcal_event(creator_email: "stranger@example.test"))
      expect(booking_for("evt-1").user).to eq(fallback)
      SubSpaceBooking.delete_all
      fallback.destroy
      described_class.process(c18_gcal_event(creator_email: "stranger@example.test"))
      expect(booking_for("evt-1").user).to be_nil
    end

    it "updates the same booking in place when the event is processed again (keyed by google_booking_id)" do
      described_class.process(c18_gcal_event)
      first = booking_for("evt-1")
      expect do
        described_class.process(c18_gcal_event(summary: "Renamed", location: "STM 126",
                                               start_at: Time.utc(2027, 4, 5, 16), end_at: Time.utc(2027, 4, 5, 17)))
      end.not_to change { [SubSpaceBooking.count, SubSpaceBookingStatus.count] }
      expect(first.reload).to have_attributes(name: "Renamed", sub_space: stm126, start_time: Time.utc(2027, 4, 5, 16))
    end

    it "re-approves nothing: an existing status is left as it is on update" do
      described_class.process(c18_gcal_event)
      booking = booking_for("evt-1")
      booking.sub_space_booking_status.update!(booking_status: create(:booking_status, :rejected))
      described_class.process(c18_gcal_event(summary: "Again"))
      expect(booking.reload.sub_space_booking_status.booking_status.name).to eq("Declined")
    end

    it "skips overlap/conflict checks: overlapping events create overlapping blocking bookings" do
      described_class.process(c18_gcal_event(id: "a"))
      described_class.process(c18_gcal_event(id: "b"))
      expect(SubSpaceBooking.where(google_booking_id: %w[a b]).count).to eq(2)
    end

    it "silently drops an all-day event (date, no date_time): nothing saved and no error" do
      # WART(D-R25): all-day events carry start.date, not start.date_time; start_time is nil so the save fails validation and the event is silently skipped 
      all_day = c18_gcal_event(id: "allday")
      all_day.start = Google::Apis::CalendarV3::EventDateTime.new(date: "2027-04-05")
      all_day.end = Google::Apis::CalendarV3::EventDateTime.new(date: "2027-04-06")
      expect { described_class.process(all_day) }.not_to raise_error
      expect(booking_for("allday")).to be_nil
    end

    it "silently drops an event ending before it starts (validation failure)" do
      expect do
        described_class.process(c18_gcal_event(start_at: Time.utc(2027, 4, 5, 16), end_at: Time.utc(2027, 4, 5, 15)))
      end.not_to change(SubSpaceBooking, :count)
    end

    it "raises NoMethodError for an event with no creator" do
      # part of WART(D-B40): event.creator.email has no nil guard, one such event aborts the whole sync batch
      expect { described_class.process(c18_gcal_event(creator_email: nil)) }.to raise_error(NoMethodError)
    end

    it "raises RecordNotFound when the SubSpace row for a valid location does not exist" do
      # part of WART(D-B40): find_by! aborts the batch if STM 124/126 was renamed or deleted
      stm126.destroy
      expect { described_class.process(c18_gcal_event(location: "STM 126")) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "delete (cancelled / missing start or end)" do
    before { described_class.process(c18_gcal_event) }

    it "deletes the booking row (and its status row, via the database cascade) without callbacks" do
      status_id = booking_for("evt-1").sub_space_booking_status.id
      expect { described_class.process(c18_gcal_event(status: "cancelled")) }.to change(SubSpaceBooking, :count).by(-1)
      expect(booking_for("evt-1")).to be_nil
      expect(SubSpaceBookingStatus.find_by(id: status_id)).to be_nil
    end

    it "treats an event with no start or no end as a deletion too" do
      described_class.process(c18_gcal_event(start_nil: true))
      expect(booking_for("evt-1")).to be_nil
    end

    it "does nothing for a cancelled event we never stored" do
      expect { described_class.process(c18_gcal_event(id: "never", status: "cancelled")) }
        .not_to change(SubSpaceBooking, :count)
    end

    it "does not delete when the cancelled event's location is not an STM room (the location filter runs first)" do
      described_class.process(c18_gcal_event(status: "cancelled", location: "Elsewhere"))
      expect(booking_for("evt-1")).to be_present
    end
  end
end
