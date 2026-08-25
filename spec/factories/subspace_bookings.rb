# frozen_string_literal: true

FactoryBot.define do
  factory :sub_space_booking do
    association :user, factory: %i[user regular_user]
    association :sub_space
    sequence(:name) { |n| "Subspace Booking #{n}" }
    description { Faker::Lorem.sentence }
    start_time { Time.zone.now }
    end_time { Time.zone.now + 1.hour }

    after(:create) do |booking|
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
