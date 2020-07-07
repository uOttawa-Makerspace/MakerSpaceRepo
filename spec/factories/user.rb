require 'faker'

FactoryBot.define do

  factory :user do

    trait :regular_user do
      id { 1 }
      username { "Bob" }
      password { "asa32A353#" }
      email {Faker::Internet.email}
      name {Faker::Lorem.words}
      read_and_accepted_waiver_form { true }
      active { true }
      role { "regular_user" }
      identity { "community_member" }
      gender { "Male" }
      wallet { 1000 }
    end

    trait :admin_user do
      id { 2 }
      username { "John" }
      password { "asa32A353#" }
      email {Faker::Internet.email}
      name {Faker::Lorem.words}
      read_and_accepted_waiver_form { true }
      active { true }
      role { "admin" }
      identity { "community_member" }
      gender { "Male" }
      wallet { 1000 }
    end

    trait :other_user do
      id { 3 }
      username { "Jim" }
      password { "asa32A353#" }
      email {Faker::Internet.email}
      name {Faker::Lorem.words}
      read_and_accepted_waiver_form { true }
      active { true }
      role { "regular_user" }
      identity { "community_member" }
      gender { "Male" }
    end

    trait :student do
      id { 4 }
      username { "Justine" }
      password { "fda3A353$" }
      email {Faker::Internet.email}
      name {Faker::Lorem.words}
      read_and_accepted_waiver_form { true }
      active { true }
      role { "regular_user" }
      identity { "undergrad" }
      program { "BASc in Software Engineering" }
      faculty { "Engineering" }
      year_of_study { 2020 }
      student_id { 234139242 }
      gender { "Female" }
    end

  end

end
