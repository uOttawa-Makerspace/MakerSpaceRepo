require 'faker'

FactoryBot.define do

  factory :user do

    trait :regular_user do
      id { 1 }
      username { "Bob" }
      password { "$2a$12$t3MkhdxmndlLDLHiJiVqBOdBAjFZWidydW/vd53.pS5ej7DcIZ1LC" }
      email {Faker::Internet.email}
      name { Faker::Lorem.words }
      read_and_accepted_waiver_form { true }
      active { true }
      role { "regular_user" }
      identity { "community_member" }
      gender { "Male" }
      wallet { 1000 }
      how_heard_about_us { Faker::Lorem.paragraph }
    end

    trait :regular_user_with_avatar do
      id { 1 }
      username { "Bob" }
      password { "asa32A353#" }
      email {Faker::Internet.email}
      name { Faker::Lorem.words }
      read_and_accepted_waiver_form { true }
      active { true }
      role { "regular_user" }
      identity { "community_member" }
      gender { "Male" }
      wallet { 1000 }
      how_heard_about_us { Faker::Lorem.paragraph }
      avatar { AvatarTestHelper.png }
    end

    trait :regular_user_with_broken_avatar do
      id { 1 }
      username { "Bob" }
      password { "asa32A353#" }
      email {Faker::Internet.email}
      name { Faker::Lorem.words }
      read_and_accepted_waiver_form { true }
      active { true }
      role { "regular_user" }
      identity { "community_member" }
      gender { "Male" }
      wallet { 1000 }
      how_heard_about_us { Faker::Lorem.paragraph }
      avatar { AvatarTestHelper.stl }
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

    trait :staff do
      username { Faker::Lorem.word }
      password { "asa32A353#" }
      email {Faker::Internet.email}
      name {Faker::Lorem.words}
      read_and_accepted_waiver_form { true }
      active { true }
      role { "staff" }
      identity { "community_member" }
      gender { "Male" }
      wallet { 1000 }
    end

    trait :volunteer do
      id { 5 }
      username { "John" }
      password { "asa32A353#" }
      email {Faker::Internet.email}
      name {Faker::Lorem.words}
      read_and_accepted_waiver_form { true }
      active { true }
      role { "volunteer" }
      identity { "community_member" }
      gender { "Male" }
      wallet { 1000 }
    end

  end

end
