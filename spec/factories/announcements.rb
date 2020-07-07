require 'faker'

FactoryBot.define do
  factory :announcement do

    trait 'volunteer' do
      description { Faker::Lorem.paragraph }
      active { true }
      public_goal { "volunteer" }
      user_id { 2 }
    end

    trait 'regular_user' do
      description { Faker::Lorem.paragraph }
      active { true }
      public_goal { "regular_user" }
      user_id { 2 }
    end

    trait 'staff' do
      description { Faker::Lorem.paragraph }
      active { true }
      public_goal { "staff" }
      user_id { 2 }
    end

    trait 'admin' do
      description { Faker::Lorem.paragraph }
      active { true }
      public_goal { "admin" }
      user_id { 2 }
    end

    trait 'all' do
      description { Faker::Lorem.paragraph }
      active { true }
      public_goal { "all" }
      user_id { 2 }
    end

  end
end
