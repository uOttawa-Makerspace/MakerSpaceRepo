require 'faker'

FactoryBot.define do
  factory :user do
    read_and_accepted_waiver_form { true }
    active { true }
    email { Faker::Internet.email }
    name { Faker::Name.name }
    username{ Faker::Name.first_name }

    trait :regular_user do
      # username { "Bob" }
      password { "asa32A353#" }
      role { "regular_user" }
      identity { "community_member" }
      gender { "Male" }
      wallet { 1000 }
    end

    trait :admin_user do
      # username { "John" }
      password { "asa32A353#" }
      role { "admin" }
      identity { "community_member" }
      gender { "Male" }
      wallet { 1000 }
    end

    trait :other_user do
      # username { "Jim" }
      password { "asa32A353#" }
      role { "regular_user" }
      identity { "community_member" }
      gender { "Male" }
    end

    trait :student do
      # username { "Justine" }
      password { "fda3A353$" }
      role { "regular_user" }
      identity { "undergrad" }
      program { "BASc in Software Engineering" }
      faculty { "Engineering" }
      year_of_study { 2020 }
      student_id { 234139242 }
      gender { "Female" }
    end

    factory :user_with_announcements do
      transient do
        announcements_count { 5 }
      end
      after(:create) do |user, evaluator|
        create_list(:announcement, evaluator.announcements_count, user: user)
      end
    end
  end
end
