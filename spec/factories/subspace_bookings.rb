FactoryBot.define do
  factory :sub_space_booking do
    user { create(:user, :regular_user) }
    name { Faker::Name.unique.name }
    description { Faker::Lorem.sentence }
    sub_space { create(:sub_space) }
    start_time { Time.zone.now }
    end_time { Time.zone.now + 1.hour }
    after :create do |booking|
      status = create(:sub_space_booking_status, sub_space_booking: booking)
      booking.update(sub_space_booking_status_id: status.id)
    end
  end
end
