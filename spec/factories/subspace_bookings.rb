# frozen_string_literal: true

FactoryBot.define do
  factory :sub_space_booking do
    association :user, factory: %i[user regular_user]
    association :sub_space
    sequence(:name) { |n| "Subspace Booking #{n}" }
    description { Faker::Lorem.sentence }
    start_time { Time.zone.now }
    end_time { Time.zone.now + 1.hour }
    # A factory row stands for a booking that already exists, so it may start
    # in the past (and the default "now" start may be a minute old by the time
    # it saves). The past-date rule (D-B18) is specced through
    # SubSpaceBooking.new and the controller. Reset after the insert, so later
    # saves of this instance are checked like those of any loaded booking.
    allow_past_start { true }

    after(:create) do |booking|
      booking.allow_past_start = false
      unless booking.sub_space_booking_status_id.present?
        pending_status = BookingStatus.find_by(name: "Pending") || create(:booking_status, :pending)
        status = SubSpaceBookingStatus.create!(
          sub_space_booking: booking,
          booking_status: pending_status
        )
        booking.update_column(:sub_space_booking_status_id, status.id)
      end
    end
  end
end
