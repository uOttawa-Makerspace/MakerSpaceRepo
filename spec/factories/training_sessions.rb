require 'faker'

FactoryBot.define do

  factory :training_session do

    trait :normal do
      id { 1 }
      training_id { 1 }
      space_id { 1 }
      level { "Beginner" }
    end

    trait :three_d do
      id { 2 }
      training_id { 3 }
      space_id { 1 }
      level { "Beginner" }
    end

    trait :basic do
      id { 3 }
      training_id { 4 }
      space_id { 2 }
      level { "Beginner" }
    end

  end

end



