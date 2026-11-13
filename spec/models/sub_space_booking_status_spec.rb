# frozen_string_literal: true

require "rails_helper"

# Characterization spec for the SubSpaceBookingStatus model: a one-row
# (has_one-style link) status table that the controller FK-dances around in
# destroy_booking (doc/architecture.md §5.3.1 plans to replace it with a
# status column on SubSpaceBooking).

RSpec.describe SubSpaceBookingStatus, type: :model do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
  end

  it "requires a booking_status (belongs_to without optional)" do
    booking = create(:sub_space_booking)
    status = described_class.new(sub_space_booking: booking)
    expect(status).not_to be_valid
  end

  it "takes the booking state from booking_status_id, whatever the old status rows say" do
    booking = create(:sub_space_booking)
    expect(booking.reload.booking_status.name).to eq("Pending")

    added = described_class.create!(
      sub_space_booking: booking,
      booking_status: @approved_status
    )
    booking.update_column(:sub_space_booking_status_id, added.id)

    booking.reload
    expect(booking.sub_space_booking_status_id).to eq(added.id)
    expect(booking).to be_pending
    expect(booking).not_to be_approved
    expect(booking.booking_status.name).to eq("Pending")
    expect(SubSpaceBooking.pending).to include(booking)
    expect(SubSpaceBooking.approved).not_to include(booking)
  end

  describe "destroy" do
    it "refuses while the booking points at it, and keeps the booking" do
      booking = create(:sub_space_booking, :with_old_status_row)
      status = booking.sub_space_booking_status

      expect(status.destroy).to be(false)

      expect(status.errors[:base]).not_to be_empty
      expect(described_class.exists?(status.id)).to be(true)
      expect(SubSpaceBooking.exists?(booking.id)).to be(true)
    end

    it "keeps the booking when a status row nothing points at is destroyed" do
      booking = create(:sub_space_booking, :with_old_status_row)
      extra = described_class.create!(sub_space_booking: booking, booking_status: @approved_status)

      expect(extra.destroy).to be_truthy

      expect(SubSpaceBooking.exists?(booking.id)).to be(true)
    end

    it "still goes with its booking through destroy_with_status!" do
      booking = create(:sub_space_booking, :with_old_status_row)
      status_id = booking.sub_space_booking_status_id

      booking.destroy_with_status!

      expect(described_class.exists?(status_id)).to be(false)
      expect(SubSpaceBooking.exists?(booking.id)).to be(false)
    end
  end
end
