# frozen_string_literal: true

require "rails_helper"

# Characterization spec for the SubSpaceBooking model.
# Pins the exact validation surface (little more than presence checks) and
# the absence of the validations the booking flow implies: there is NO
# overlap rule and NO past-date rule (probes through controller flows pinned
# those consequences separately).

RSpec.describe SubSpaceBooking, type: :model do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
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

    it "WART: allows two overlapping bookings (no overlap validation)" do
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
      expect(existing.reload).to be_present
    end

    it "WART: past-dated bookings are valid (no past-date rule)" do
      b = described_class.new(
        sub_space: create(:sub_space),
        name: "Ancient", description: "D",
        start_time: 2.years.ago.to_datetime,
        end_time: 2.years.ago.to_datetime + 1.hour
      )
      expect(b).to be_valid
    end

    # WART: has_one :sub_space_booking_status (dependent: :destroy) deletes
    # the STATUS row first, while sub_space_bookings.
    # sub_space_booking_status_id still references it — PG 23503 raises and
    # the booking SURVIVES, destroy is effectively a no-op. This is why the
    # controller has a manual FK dance in destroy_booking (request-spec
    # pinned).
    it "WART: destroy raises InvalidForeignKey and the row survives" do
      booking = create(:sub_space_booking, name: "N", description: "D",
                       start_time: DateTime.parse("2027-03-03 10:00"),
                       end_time: DateTime.parse("2027-03-03 11:00"))
      status_row = described_class
                   .find(booking.id).sub_space_booking_status

      expect { booking.destroy }
        .to raise_error(ActiveRecord::InvalidForeignKey)
      expect(booking.reload).to be_present
      expect(status_row.reload).to be_present
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
      made.sub_space_booking_status
          .update!(booking_status_id: status_row.id)
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
end
