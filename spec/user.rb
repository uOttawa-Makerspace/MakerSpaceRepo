require 'faker'

FactoryGirl.define do
  factory :user1, class: User do
    id 1
    username { Faker::Lorem.word }
    password {Faker::Lorem.word}
    email {Faker::Internet.email}
    name {Faker::Lorem.words}
    read_and_accepted_waiver_form true
    active true
    role "regular_user"
    identity "community_member"

  end

end
