FactoryBot.define do
  factory :sub_space_booking_status do
    booking_status { BookingStatus::PENDING }
  end
end
