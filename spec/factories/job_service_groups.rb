# frozen_string_literal: true

FactoryBot.define do
  factory :job_service_group do
    sequence(:name) { |n| "Service Group #{n}" }
    description { Faker::Lorem.sentence }
    multiple { false }
    text_field { false }
    association :job_type
  end
end
