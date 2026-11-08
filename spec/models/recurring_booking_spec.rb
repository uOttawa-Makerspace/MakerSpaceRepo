# frozen_string_literal: true

require "rails_helper"

# RecurringBooking holds NO columns beyond timestamps — it is a group handle:
# sub space bookings point at it via recurring_booking_id. Its has_many
# dependent: :destroy cascade never actually completes (FK constraint, see below).

RSpec.describe RecurringBooking, :booking_clock, type: :model do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
  end

  it "can be saved empty (no validations) and survives alone" do
    recurring = described_class.create!
    expect(described_class.exists?(recurring.id)).to be(true)
    expect(recurring.sub_space_bookings).to be_empty
  end

  # destroying a group deletes nothing: each booking's status row refuses its destroy while the booking
  # points at it, so the group's destroy is refused.
  it "destroy is refused and deletes NOTHING" do
    recurring = described_class.create!
    bookings = 3.times.map {
      create(:sub_space_booking, recurring_booking: recurring,
             start_time: DateTime.parse("2027-03-03 10:00"),
             end_time: DateTime.parse("2027-03-03 11:00"))
    }
    expect(recurring.sub_space_bookings.count).to eq(3)

    expect(recurring.destroy).to be(false)
    expect(described_class.exists?(recurring.id)).to be(true)
    expect(SubSpaceBooking.where(id: bookings.map(&:id)).count).to eq(3)
    expect(SubSpaceBookingStatus.where(sub_space_booking_id: bookings.map(&:id)).count).to eq(3)
  end
end
