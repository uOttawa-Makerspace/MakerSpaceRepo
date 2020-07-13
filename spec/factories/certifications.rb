require 'faker'

FactoryBot.define do

  factory :certification do

    association :user, :regular_user

    trait :first do
      association :training_session, :normal
    end

    trait :three_d do
      association :training_session, :three_d
    end

    trait :basic do
      association :training_session, :basic
    end

  end

end




