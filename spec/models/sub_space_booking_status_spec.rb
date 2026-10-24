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
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
  end

  it "requires a booking_status (belongs_to without optional)" do
    booking = create(:sub_space_booking)
    status = described_class.new(sub_space_booking: booking)
    expect(status).not_to be_valid
  end

  it "links a booking to a booking_status one-to-one" do
    booking = create(:sub_space_booking)
    # the factory already linked a Pending status; reload shows that lookup
    # still resolves by the STATUS row's sub_space_booking_id, not the
    # booking's cached sub_space_booking_status_id column.
    first_status = booking.reload.sub_space_booking_status
    expect(first_status.booking_status.name).to eq("Pending")

    added = described_class.create!(
      sub_space_booking: booking,
      booking_status: @approved_status
    )
    booking.update_column(:sub_space_booking_status_id, added.id)
    expect(booking.reload.sub_space_booking_status_id).to eq(added.id)
    # WART: has_one points at the FIRST matching status row — the extra
    # approved row would only surface through the id column.
    expect(booking.reload.sub_space_booking_status.booking_status.name)
      .to eq("Pending")
  end
end
