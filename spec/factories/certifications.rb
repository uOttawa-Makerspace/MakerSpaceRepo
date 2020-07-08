require 'faker'

FactoryBot.define do

  factory :certification do

    trait :first do
      training_session_id { 1 }
    end

    trait :three_d do
      training_session_id { 2 }
    end

    trait :basic do
      training_session_id { 3 }
    end

  end

end




