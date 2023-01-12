FactoryBot.define do
  factory :sub_space_booking_status do
    booking_status_id { BookingStatus.find_by(name: "Pending").id }
  end
end
