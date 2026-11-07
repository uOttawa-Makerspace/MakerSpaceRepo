# frozen_string_literal: true

require "rails_helper"

# Characterization spec for the SubSpaceBooking model.
# Pins the exact validation surface: presence checks, the time order, and the
# past-date rule (a booking may not be created or moved to start in the
# past). There is NO overlap rule (overlap is intended); probes through
# controller flows pinned those consequences separately.

RSpec.describe SubSpaceBooking, :booking_clock, type: :model do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
  end

  describe "#destroy_with_status!" do
    it "destroys the booking and its status row" do
      booking = create(:sub_space_booking)
      status_id = booking.sub_space_booking_status_id

      booking.destroy_with_status!

      expect(described_class.exists?(booking.id)).to be(false)
      expect(SubSpaceBookingStatus.exists?(status_id)).to be(false)
    end

    it "destroys a booking that has no status" do
      booking = create(:sub_space_booking)
      booking.update_column(:sub_space_booking_status_id, nil)
      SubSpaceBookingStatus.where(sub_space_booking_id: booking.id).delete_all

      expect { described_class.find(booking.id).destroy_with_status! }
        .to change(described_class, :count).by(-1)
    end

    it "leaves the booking and its status linked when the destroy fails" do
      booking = create(:sub_space_booking)
      status_id = booking.sub_space_booking_status_id
      allow_any_instance_of(described_class).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)

      expect { described_class.find(booking.id).destroy_with_status! }.to raise_error(ActiveRecord::RecordNotDestroyed)

      expect(booking.reload.sub_space_booking_status_id).to eq(status_id)
      expect(SubSpaceBookingStatus.find(status_id).sub_space_booking_id).to eq(booking.id)
    end
  end

  describe "status" do
    let(:booking) { create(:sub_space_booking) }

    def legacy_status(record)
      SubSpaceBookingStatus.find_by(sub_space_booking_id: record.id)&.booking_status
    end

    it "is pending, approved or declined, and the scopes follow it" do
      booking.change_status!(@approved_status)
      expect(booking.reload).to be_approved
      expect(booking).not_to be_pending
      expect(described_class.approved).to contain_exactly(booking)
      expect(described_class.pending).to be_empty
      booking.change_status!(@declined_status)
      expect(booking.reload).to be_declined
      expect(described_class.declined).to contain_exactly(booking)
    end

    it "must exist when one is given" do
      booking.booking_status_id = -1
      expect(booking).not_to be_valid
      expect(booking.errors[:booking_status]).to be_present
    end

    describe "#save_with_status!" do
      it "saves the booking with the status and a matching old status row, linked" do
        new_booking = build(:sub_space_booking, booking_status: nil)

        new_booking.save_with_status!(@approved_status)

        expect(new_booking.reload.booking_status).to eq(@approved_status)
        expect(legacy_status(new_booking)).to eq(@approved_status)
        expect(new_booking.sub_space_booking_status_id).to eq(SubSpaceBookingStatus.find_by(sub_space_booking_id: new_booking.id).id)
      end

      it "saves nothing when the booking is invalid" do
        new_booking = build(:sub_space_booking, booking_status: nil, name: nil)

        expect { new_booking.save_with_status!(@approved_status) }.to raise_error(ActiveRecord::RecordInvalid)

        expect(described_class.count).to eq(0)
        expect(SubSpaceBookingStatus.count).to eq(0)
      end
    end

    describe "#change_status!" do
      it "sets the status and keeps the old status row in step" do
        booking.change_status!(@approved_status)

        expect(booking.reload.booking_status).to eq(@approved_status)
        expect(legacy_status(booking)).to eq(@approved_status)
        expect(SubSpaceBookingStatus.where(sub_space_booking_id: booking.id).count).to eq(1)
      end

      it "creates the old status row when the booking has none" do
        booking.update_column(:sub_space_booking_status_id, nil)
        SubSpaceBookingStatus.where(sub_space_booking_id: booking.id).delete_all

        described_class.find(booking.id).change_status!(@declined_status)

        expect(legacy_status(booking)).to eq(@declined_status)
        expect(booking.reload.sub_space_booking_status_id).to be_present
      end

      it "works on a booking that no longer passes validation" do
        booking.update_columns(end_time: booking.start_time - 1.hour)

        described_class.find(booking.id).change_status!(@approved_status)

        expect(booking.reload).to be_approved
      end
    end

    describe ".change_status_of!" do
      it "changes the listed bookings and their old status rows, and no others" do
        listed = create_list(:sub_space_booking, 2)
        other = create(:sub_space_booking)

        described_class.change_status_of!(listed, @declined_status)

        expect(listed.map { |b| b.reload.booking_status }).to all(eq(@declined_status))
        expect(listed.map { |b| legacy_status(b) }).to all(eq(@declined_status))
        expect(other.reload.booking_status).to eq(@pending_status)
        expect(legacy_status(other)).to eq(@pending_status)
      end
    end
  end

  describe "validations" do
    it "needs name, description, start_time, end_time (i18n full messages)" do
      blank = described_class.new(sub_space: nil)
      expect(blank.valid?).to be(false)
      expect(blank.errors.full_messages).to eq(
        [
          "Sub space must exist",
          "Name This field is required.",
          "Description This field is required.",
          "Start time This field is required.",
          "End time This field is required."
        ]
      )
    end

    # the error lands on :expiration_date
    it "rejects start >= end under the Expiration date message" do
      b = described_class.new(
        sub_space: create(:sub_space),
        name: "N", description: "D",
        start_time: DateTime.parse("2027-03-03 10:00"),
        end_time: DateTime.parse("2027-03-03 10:00")
      )
      expect(b).not_to be_valid
      expect(b.errors.full_messages)
        .to eq(["Expiration date Start Time needs to be before end time"])
    end

    # no overlap validation
    it "allows two overlapping bookings (no overlap validation)" do
      subspace = create(:sub_space)
      existing = create(:sub_space_booking, sub_space: subspace,
             start_time: DateTime.parse("2027-03-03 10:00"),
             end_time: DateTime.parse("2027-03-03 12:00"))
      overlapping = described_class.new(
        sub_space: subspace, user: existing.user,
        name: "Over", description: "D",
        start_time: DateTime.parse("2027-03-03 11:00"),
        end_time: DateTime.parse("2027-03-03 12:00")
      )
      expect(overlapping).to be_valid
      expect(overlapping.save!).to be_truthy
      expect(described_class.where(sub_space: subspace).order(:id).pluck(:name))
        .to eq([existing.name, "Over"])
    end

    describe "past-date rule" do
      let(:room) { create(:sub_space) }

      def fresh(start_time, end_time = start_time + 1.hour)
        described_class.new(sub_space: room, name: "N", description: "D",
                            start_time: start_time, end_time: end_time)
      end

      it "rejects a new booking that starts in the past, with the i18n message" do
        b = fresh(2.years.ago)
        expect(b).not_to be_valid
        expect(b.errors.full_messages)
          .to eq(["Start time cannot be in the past. Pick a start time from now on."])
        expect(b.errors.of_kind?(:start_time, :in_the_past)).to be(true)
      end

      it "rejects a start one minute ago, even when the booking is still running" do
        expect(fresh(1.minute.ago, 1.hour.from_now)).not_to be_valid
      end

      it "accepts a start in the current minute and any later one" do
        expect(fresh(Time.current.beginning_of_minute)).to be_valid
        expect(fresh(1.minute.from_now)).to be_valid
      end

      it "has a French message" do
        b = fresh(1.day.ago)
        b.valid?
        expect(I18n.with_locale(:fr) { b.errors.full_messages }).to eq(
          ["Start time ne peut pas être dans le passé. Choisissez une heure de début à partir de maintenant."]
        )
      end

      it "lets an existing past booking save when its times stay put" do
        old = create(:sub_space_booking, sub_space: room, start_time: 3.days.ago, end_time: 3.days.ago + 1.hour)
        old = described_class.find(old.id)
        old.name = "Renamed"
        old.public = true
        old.start_time = old.start_time # an unchanged value is not a change
        expect(old.save).to be(true)
        expect(old.reload.name).to eq("Renamed")
      end

      it "refuses to move an existing booking so that it starts in the past" do
        future = described_class.find(create(:sub_space_booking, sub_space: room,
                                                                 start_time: 1.day.from_now,
                                                                 end_time: 1.day.from_now + 1.hour).id)
        expect(future.update(start_time: 1.day.ago)).to be(false)
        expect(future.errors.of_kind?(:start_time, :in_the_past)).to be(true)
      end

      # a booking in progress may move
      # its END, if the start stays put and the new end is after now.
      describe "a booking already in progress" do
        def in_progress
          described_class.find(create(:sub_space_booking, sub_space: room,
                                                          start_time: 1.hour.ago,
                                                          end_time: 1.hour.from_now).id)
        end

        it "may be extended" do
          booking = in_progress
          expect(booking.update(end_time: 2.hours.from_now)).to be(true)
        end

        it "may be shortened to an end after now" do
          booking = in_progress
          expect(booking.update(end_time: 1.minute.from_now)).to be(true)
        end

        it "may not end in the past (or right now): the error is on end_time, en and fr" do
          booking = in_progress
          expect(booking.update(end_time: Time.current)).to be(false)
          expect(booking.update(end_time: 10.minutes.ago)).to be(false)
          expect(booking.errors.of_kind?(:end_time, :in_the_past)).to be(true)
          expect(booking.errors.full_messages).to eq(
            ["End time cannot be in the past for a booking that has already started. Pick an end time after now."]
          )
          expect(I18n.with_locale(:fr) { booking.errors.full_messages }).to eq(
            ["End time ne peut pas être dans le passé pour une réservation déjà commencée. " \
             "Choisissez une heure de fin après maintenant."]
          )
        end

        it "may not move its start, even with the end in the future" do
          booking = in_progress
          expect(booking.update(start_time: 30.minutes.ago, end_time: 2.hours.from_now)).to be(false)
          expect(booking.errors.of_kind?(:start_time, :in_the_past)).to be(true)
        end

        it "a booking that has not started may move only its end" do
          booking = described_class.find(create(:sub_space_booking, sub_space: room,
                                                                    start_time: 1.hour.from_now,
                                                                    end_time: 2.hours.from_now).id)
          expect(booking.update(end_time: 3.hours.from_now)).to be(true)
        end

        it "a booking that already ended may not have its times changed at all" do
          ended = described_class.find(create(:sub_space_booking, sub_space: room,
                                                                  start_time: 3.hours.ago,
                                                                  end_time: 1.hour.ago).id)
          expect(ended.update(end_time: 2.hours.ago)).to be(false)
          expect(ended.errors.of_kind?(:end_time, :booking_ended)).to be(true)
        end
      end

      it "compares the times at minute precision: resubmitting 09:00 for a stored 09:00:30 is not a move" do
        stored = Time.zone.parse("2026-11-30 09:00:30") # past at BookingClock::NOW
        row = create(:sub_space_booking, sub_space: room, start_time: stored, end_time: stored + 1.hour)
        row = described_class.find(row.id)
        expect(row.start_time.sec).to eq(30)
        row.assign_attributes(name: "Renamed", start_time: "2026-11-30 09:00", end_time: "2026-11-30 10:00")
        expect(row.save).to be(true)
        expect(row.reload.name).to eq("Renamed")
      end

      it "judges against reference_time when it is set (one clock read per request)" do
        b = fresh(10.minutes.ago)
        b.reference_time = 1.hour.ago
        expect(b).to be_valid
        b.reference_time = Time.current
        expect(b).not_to be_valid
      end

      it "past_start_message is the full start-time error, built without a record (en and fr)" do
        expect(described_class).not_to receive(:new)
        expect(described_class.past_start_message)
          .to eq("Start time cannot be in the past. Pick a start time from now on.")
        expect(I18n.with_locale(:fr) { described_class.past_start_message })
          .to eq("Start time ne peut pas être dans le passé. Choisissez une heure de début à partir de maintenant.")
      end

      # The start and the end are both judged against the current minute.
      it "rounds now to the minute for the end check too" do
        booking = described_class.find(create(:sub_space_booking, sub_space: room,
                                                                  start_time: 1.hour.ago,
                                                                  end_time: 1.hour.from_now).id)
        travel_to(BookingClock::NOW + 30.seconds)
        expect(booking.update(end_time: BookingClock::NOW + 20.seconds)).to be(true) # this minute
        expect(booking.update(end_time: BookingClock::NOW - 1.second)).to be(false)  # the minute before
        expect(booking.errors.of_kind?(:end_time, :in_the_past)).to be(true)
      end

      it "times_changing? compares at minute precision" do
        stored = Time.zone.parse("2026-12-03 09:00:30")
        row = described_class.find(create(:sub_space_booking, sub_space: room,
                                                              start_time: stored, end_time: stored + 1.hour).id)
        row.start_time = "2026-12-03 09:00"
        expect(row.times_changing?).to be(false)
        row.start_time = "2026-12-03 09:01"
        expect(row.times_changing?).to be(true)
      end

      # The factory's bypass covers only its own INSERT.
      it "checks a factory-built record like any other" do
        expect(build(:sub_space_booking, sub_space: room, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour))
          .not_to be_valid
        created = create(:sub_space_booking, sub_space: room, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
        expect(created.allow_past_start).to be_nil
        expect(created.update(start_time: 2.days.ago)).to be(false)
      end

      it "lets the Google Calendar mirror (allow_past_start) save a past event" do
        b = fresh(1.week.ago)
        b.allow_past_start = true
        expect(b).to be_valid
      end
    end

    # has_one :sub_space_booking_status (dependent: :destroy) deletes
    # the STATUS row first, while sub_space_bookings.
    # sub_space_booking_status_id still references it — PG 23503 raises and
    # the booking SURVIVES, destroy is effectively a no-op. This is why the
    # controller has a manual FK dance in destroy_booking (request-spec
    # pinned).
    it "destroy raises InvalidForeignKey and the row survives" do
      booking = create(:sub_space_booking, name: "N", description: "D",
                       start_time: DateTime.parse("2027-03-03 10:00"),
                       end_time: DateTime.parse("2027-03-03 11:00"))
      status_row = described_class
                   .find(booking.id).sub_space_booking_status

      expect { booking.destroy }
        .to raise_error(ActiveRecord::InvalidForeignKey)
      expect(described_class.exists?(booking.id)).to be(true)
      expect(SubSpaceBookingStatus.exists?(status_row.id)).to be(true)
    end

    it "allows a nil user + nil recurring booking (optional belongs_to)" do
      b = described_class.new(
        sub_space: create(:sub_space),
        name: "Lonely", description: "D",
        start_time: DateTime.parse("2027-03-03 10:00"),
        end_time: DateTime.parse("2027-03-03 11:00")
      )
      expect(b.user).to be_nil
      expect(b.recurring_booking).to be_nil
      expect(b).to be_valid
    end
  end

  describe "COLOR_LEGEND constant" do
    it "pins the exact 5-entry legend in order" do
      expect(described_class.color_legend).to eq(
        [
          { id: "your_pending_bookings", name: "Your Pending Bookings", color: "#B5A500" },
          { id: "your_confirmed_bookings", name: "Your Confirmed Bookings", color: "#49794b" },
          { id: "other_pending_bookings", name: "Other Pending Bookings", color: "#FFA500" },
          { id: "other_confirmed_bookings", name: "Other Confirmed Bookings", color: "#497979" },
          { id: "blocking_booking", name: "Blocking Bookings", color: "#ABABABFF" }
        ]
      )
    end
  end

  describe "#color" do
    let(:user) { create(:user, :regular_user, booking_approval: true) }
    let(:subspace) { create(:sub_space) }

    def booking(status_row = @approved_status, **attrs)
      made = create(:sub_space_booking, { sub_space: subspace, user: user,
                   start_time: DateTime.parse("2027-04-05 10:00"),
                   end_time: DateTime.parse("2027-04-05 11:00") }.merge(attrs))
      made.change_status!(status_row)
      made
    end

    it "maps the 4 status colors, blocking first" do
      expect(booking(@pending_status).color(user.id)).to eq("#B5A500")
      expect(booking(@approved_status).color(user.id)).to eq("#49794b")
      expect(booking(@pending_status, user: create(:user)).color(user.id))
        .to eq("#FFA500")
      expect(booking(@approved_status, user: create(:user)).color(user.id))
        .to eq("#497979")
      expect(booking(@approved_status, blocking: true, user: create(:user))
               .color(user.id)).to eq("#ABABABFF")
    end

    it "blocking colors win over status even when owner views it" do
      expect(booking(@approved_status, blocking: true).color(user.id))
        .to eq("#ABABABFF")
    end
  end

  describe "Google calendar used for bookings" do
    let(:shared_calendar) { "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com" }
    let(:service) { instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil) }

    before do
      allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service)
      allow(described_class).to receive(:authorizer).and_return(double("auth"))
    end

    ["STM 124", "STM 126", "Another room"].each do |name|
      it "inserts and deletes bookings of #{name} on the shared booking calendar" do
        booking = create(:sub_space_booking, sub_space: create(:sub_space, name: name))
        expect(service).to receive(:insert_event)
          .with(shared_calendar, anything).and_return(double(id: "g1"))
        described_class.upsert_booking(booking)
        expect(booking.reload.google_booking_id).to eq("g1")

        expect(service).to receive(:delete_event).with(shared_calendar, "g1")
        described_class.delete_booking(booking)
      end
    end

    it "is the calendar the event publisher falls back to for spaces it does not list" do
      expect(GoogleCalendar::EventPublisher.calendar_id_for(create(:space, name: "Elsewhere")))
        .to eq(shared_calendar)
    end
  end
end
