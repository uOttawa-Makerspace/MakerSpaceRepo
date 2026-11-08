# frozen_string_literal: true

FactoryBot.define do
  factory :sub_space_booking do
    association :user, factory: %i[user regular_user]
    association :sub_space
    sequence(:name) { |n| "Subspace Booking #{n}" }
    description { Faker::Lorem.sentence }
    booking_status { BookingStatus.find_by(name: "Pending") || association(:booking_status, :pending) }
    start_time { Time.zone.now }
    end_time { Time.zone.now + 1.hour }
    # A created factory row stands for a booking that already exists, so its
    # INSERT may start in the past (and the default "now" start may be a minute
    # old by the time it saves). The bypass covers only that insert: built
    # records, and later saves of a created one, are checked by the past-date
    # rule like any other booking.
    to_create do |booking|
      booking.allow_past_start = true
      booking.save_with_status!(booking.booking_status)
    ensure
      booking.allow_past_start = nil
    end
  end
end
