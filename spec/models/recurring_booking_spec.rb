# frozen_string_literal: true

require "rails_helper"

# RecurringBooking holds NO columns beyond timestamps — it is a group handle:
# sub space bookings point at it via recurring_booking_id. Its has_many
# dependent: :destroy cascade never actually completes (FK wart, see below).

RSpec.describe RecurringBooking, type: :model do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
  end

  it "can be saved empty (no validations) and survives alone" do
    recurring = described_class.create!
    expect(described_class.exists?(recurring.id)).to be(true)
    expect(recurring.sub_space_bookings).to be_empty
  end

  # WART(D-B17): destroying a group deletes NOTHING — PG raises InvalidForeignKey
  # because the bookings' has_one :sub_space_booking_status dependent
  # :destroy deletes the STATUS row first while
  # sub_space_bookings.sub_space_booking_status_id still references it
  # (that FK has no on_delete rule). The controller's destroy_booking
  # exists to work around exactly this (request-spec pinned).
  it "destroy raises InvalidForeignKey and deletes NOTHING" do
    recurring = described_class.create!
    bookings = 3.times.map {
      create(:sub_space_booking, recurring_booking: recurring,
             start_time: DateTime.parse("2027-03-03 10:00"),
             end_time: DateTime.parse("2027-03-03 11:00"))
    }
    expect(recurring.sub_space_bookings.count).to eq(3)

    expect { recurring.destroy }
      .to raise_error(ActiveRecord::InvalidForeignKey)
    expect(described_class.exists?(recurring.id)).to be(true)
    expect(SubSpaceBooking.where(id: bookings.map(&:id)).count).to eq(3)
  end
end
