require 'faker'

FactoryGirl.define do
  factory :repo1, class: Repository do
    id 1
    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
    share_type "public"
    after(:create) do
      create(:user1)
    end
  end

end