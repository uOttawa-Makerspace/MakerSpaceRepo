FactoryBot.define do
  factory :program do
    association :user, :regular_user
    program_type { Faker::Lorem.word }

    trait :development_program do
      program_type { Program::DEV_PROGRAM }
    end

    trait :volunteer_program do
      program_type { Program::VOLUNTEER }
    end
  end
end
