require 'faker'

FactoryBot.define do

  factory :user do
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
  end

end
