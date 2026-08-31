FactoryBot.define do
  factory :sub_space_booking_status do
    association :sub_space_booking
    booking_status do
      BookingStatus.find_by(name: "Pending") || association(:booking_status, :pending)
    end
  end
end
