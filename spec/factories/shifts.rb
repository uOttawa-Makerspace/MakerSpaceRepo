# frozen_string_literal: true

FactoryBot.define do
  factory :shift do
    association :space
    start_datetime { Time.zone.now }
    end_datetime { Time.zone.now + 1.hour }
    reason { Faker::Lorem.word }

    after(:build) do |shift|
      shift.users << build(:user, :staff) if shift.users.empty?
    end
  end
end
