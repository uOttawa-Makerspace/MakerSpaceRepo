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
      expect(booking.booking_status).to eq(approved)
      expect(booking.sub_space_booking_status).to have_attributes(booking_status: approved, id: booking.sub_space_booking_status_id)
    end

    it "saves nothing and reports when the status of the new booking cannot be saved" do
      allow(BookingStatus).to receive(:approved).and_return(BookingStatus.new(id: -1, name: "Ghost"))
      expect(Rails.error).to receive(:report)
        .with(instance_of(ActiveRecord::RecordInvalid), hash_including(handled: true, context: { google_event_id: "evt-1" }))

      described_class.process(c18_gcal_event)

      expect(SubSpaceBooking.count).to eq(0)
      expect(SubSpaceBookingStatus.count).to eq(0)
    end

    # the past-date rule is for bookings made in the app. A full sync
    # lists past events too, and the mirror keeps them.
    it "mirrors an event that is already in the past" do
      described_class.process(c18_gcal_event(start_at: 1.week.ago.utc, end_at: 1.week.ago.utc + 1.hour))
      booking = booking_for("evt-1")
      expect(booking).to be_persisted
      expect(booking.booking_status).to eq(approved)
    end

    it "defaults a blank summary/description to 'Google Calendar Event' / 'No description'" do
      described_class.process(c18_gcal_event(summary: "", description: nil))
      expect(booking_for("evt-1")).to have_attributes(name: "Google Calendar Event", description: "No description")
    end

    describe "owner of an event whose creator has no account" do
      let!(:fallback) { create(:user, :regular_user, email: "calendar-fallback@example.com") }

      def import_from_stranger
        described_class.process(c18_gcal_event(creator_email: "stranger@example.test"))
        booking_for("evt-1")
      end

      it "is nobody when no fallback email is configured" do
        stub_const("ENV", ENV.to_hash.except("GOOGLE_CALENDAR_FALLBACK_EMAIL"))
        expect(import_from_stranger.user).to be_nil
      end

      it "is the user named by the google_calendar_fallback_email setting" do
        Setting.set("google_calendar_fallback_email", "calendar-fallback@example.com")
        expect(import_from_stranger.user).to eq(fallback)
      end

      it "is the user named by GOOGLE_CALENDAR_FALLBACK_EMAIL when the setting is blank" do
        Setting.set("google_calendar_fallback_email", "")
        stub_const("ENV", ENV.to_hash.merge("GOOGLE_CALENDAR_FALLBACK_EMAIL" => "calendar-fallback@example.com"))
        expect(import_from_stranger.user).to eq(fallback)
      end

      it "prefers the setting over the environment variable" do
        from_env = create(:user, :regular_user, email: "env@example.test")
        stub_const("ENV", ENV.to_hash.merge("GOOGLE_CALENDAR_FALLBACK_EMAIL" => from_env.email))
        Setting.set("google_calendar_fallback_email", "calendar-fallback@example.com")
        expect(import_from_stranger.user).to eq(fallback)
      end

      it "keeps the stored owner when a re-synced event resolves to nobody" do
        stub_const("ENV", ENV.to_hash.except("GOOGLE_CALENDAR_FALLBACK_EMAIL"))
        described_class.process(c18_gcal_event)
        expect(booking_for("evt-1").user).to eq(creator)
        creator.update_columns(email: "renamed@example.test")

        expect(import_from_stranger.user).to eq(creator)
        expect(booking_for("evt-1").user_id).to eq(creator.id)
      end

      it "replaces the stored owner with the fallback user once one is configured" do
        stub_const("ENV", ENV.to_hash.except("GOOGLE_CALENDAR_FALLBACK_EMAIL"))
        described_class.process(c18_gcal_event)
        Setting.set("google_calendar_fallback_email", fallback.email)

        expect(import_from_stranger.user).to eq(fallback)
      end

      it "replaces the stored owner with the creator's account when the creator has one" do
        described_class.process(c18_gcal_event(creator_email: "stranger@example.test"))
        expect(booking_for("evt-1").user).to be_nil
        described_class.process(c18_gcal_event)
        expect(booking_for("evt-1").user).to eq(creator)

        other = create(:user, :regular_user, email: "other-creator@example.test")
        described_class.process(c18_gcal_event(creator_email: other.email))
        expect(booking_for("evt-1").user).to eq(other)
      end

      it "is nobody when the configured email names no user" do
        Setting.set("google_calendar_fallback_email", "nobody-here@example.com")
        expect(import_from_stranger.user).to be_nil
      end
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
      booking.change_status!(create(:booking_status, :rejected))
      described_class.process(c18_gcal_event(summary: "Again"))
      expect(booking.reload.booking_status.name).to eq("Declined")
    end

    it "skips overlap/conflict checks: overlapping events create overlapping blocking bookings" do
      described_class.process(c18_gcal_event(id: "a"))
      described_class.process(c18_gcal_event(id: "b"))
      expect(SubSpaceBooking.where(google_booking_id: %w[a b]).count).to eq(2)
    end

    def all_day_event(id, from, to)
      event = c18_gcal_event(id: id)
      event.start = Google::Apis::CalendarV3::EventDateTime.new(date: from)
      event.end = Google::Apis::CalendarV3::EventDateTime.new(date: to)
      event
    end

    it "books an all-day event from midnight to midnight Toronto time (stored in UTC), end date exclusive" do
      described_class.process(all_day_event("allday", "2027-04-05", "2027-04-06"))
      expect(booking_for("allday")).to have_attributes(
        start_time: Time.utc(2027, 4, 5, 4), end_time: Time.utc(2027, 4, 6, 4), blocking: true
      )
    end

    it "keeps midnight Toronto time for an all-day event across the clocks going back (2026-11-01)" do
      described_class.process(all_day_event("fall", "2026-11-01", "2026-11-02"))
      # 2026-11-01 00:00 is still EDT (UTC-4); 2026-11-02 00:00 is EST (UTC-5): a 25 hour day
      expect(booking_for("fall")).to have_attributes(
        start_time: Time.utc(2026, 11, 1, 4), end_time: Time.utc(2026, 11, 2, 5)
      )
    end

    it "books a multi-day all-day event through the day before its end date" do
      described_class.process(all_day_event("multi", "2027-03-13", "2027-03-16"))
      expect(booking_for("multi")).to have_attributes(
        start_time: Time.utc(2027, 3, 13, 5), end_time: Time.utc(2027, 3, 16, 4)
      )
    end

    it "stores a timed event's instant unchanged across the clocks going back" do
      described_class.process(c18_gcal_event(id: "timed", start_at: Time.utc(2026, 11, 1, 5), end_at: Time.utc(2026, 11, 1, 7)))
      expect(booking_for("timed")).to have_attributes(start_time: Time.utc(2026, 11, 1, 5), end_time: Time.utc(2026, 11, 1, 7))
    end

    it "skips and reports an event with neither a date_time nor a date" do
      empty = c18_gcal_event(id: "empty")
      empty.start = Google::Apis::CalendarV3::EventDateTime.new
      empty.end = Google::Apis::CalendarV3::EventDateTime.new
      expect(Rails.error).to receive(:report).with(instance_of(ActiveRecord::RecordInvalid), hash_including(handled: true))
      expect { described_class.process(empty) }.not_to raise_error
      expect(booking_for("empty")).to be_nil
    end

    it "skips and reports an event ending before it starts (validation failure)" do
      expect(Rails.error).to receive(:report).with(instance_of(ActiveRecord::RecordInvalid), hash_including(handled: true))
      expect do
        described_class.process(c18_gcal_event(start_at: Time.utc(2027, 4, 5, 16), end_at: Time.utc(2027, 4, 5, 15)))
      end.not_to change(SubSpaceBooking, :count)
    end

    it "treats an event with no creator like an unknown creator (fallback owner, else nobody)" do
      expect { described_class.process(c18_gcal_event(id: "no-creator", creator_email: nil)) }.not_to raise_error
      expect(booking_for("no-creator").user).to be_nil

      fallback = create(:user, :regular_user, email: "calendar-fallback@example.com")
      Setting.set("google_calendar_fallback_email", fallback.email)
      described_class.process(c18_gcal_event(creator_email: nil))
      expect(booking_for("evt-1").user).to eq(fallback)
    end

    it "reports and skips an event whose SubSpace row does not exist, without raising" do
      stm126.destroy
      expect(Rails.error).to receive(:report).with(instance_of(ActiveRecord::RecordNotFound), hash_including(handled: true))
      expect { described_class.process(c18_gcal_event(location: "STM 126")) }.not_to raise_error
      expect(booking_for("evt-1")).to be_nil
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
