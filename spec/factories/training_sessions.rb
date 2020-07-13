require 'faker'

FactoryBot.define do

  factory :training_session do
    level { "Beginner" }
    association :user, :admin

    trait :normal do
      association :space, :makerspace
      association :training, :test
    end

    trait :three_d do
      association :space, :makerspace
      association :training, :three_d
    end

    trait :basic do
      association :space, :brunsfield
      association :training, :basic
    end

  end

end



