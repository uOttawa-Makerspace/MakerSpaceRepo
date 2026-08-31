# frozen_string_literal: true

FactoryBot.define do
  factory :space do
    sequence(:name) { |n| "Space#{n}#{SecureRandom.hex(3)}" }
    sequence(:keycode) { |n| "KEY#{n}#{SecureRandom.hex(3)}" }

    trait :with_space_managers do
      after :create do |space|
        2.times do
          space.space_managers << create(:user, :admin)
        end
      end
    end
  end
end
