FactoryBot.define do
  factory :certification do
    association :user, :regular_user
    association :training_session

    level { "Beginner" }

    trait :"3d_printing" do
      association :training_session, :"3d_printing"
    end

    trait :basic_training do
      association :training_session, :basic_training
    end

    trait "inactive" do
      active { false }
    end
  end
end
