require 'faker'

FactoryBot.define do

  factory :like do

    trait :repo1 do
      user_id { 1 }
      repository_id { 1 }

    end

    trait :repo2 do
      user_id { 1 }
      repository_id { 2 }
    end

  end
end

