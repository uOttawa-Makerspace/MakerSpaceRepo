# frozen_string_literal: true

FactoryBot.define do
  factory :sub_space do
    name { Faker::Lorem.word }
    association :space
  end
end
