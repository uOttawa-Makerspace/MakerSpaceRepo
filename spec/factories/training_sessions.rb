FactoryBot.define do
  factory :training_session do
    association :user, :admin
    association :space
    association :training
    level { "Beginner" }

    trait :normal do
      association :training, :test
    end

    trait :'3d_printing' do
      association :training, :'3d_printing'
    end

    trait :basic_training do
      association :training, :basic_training
    end
  end
end



