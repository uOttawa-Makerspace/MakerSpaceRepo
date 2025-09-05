FactoryBot.define do
  factory :training_requirement do
    association :training
    association :proficient_project

    trait :"3d_printing" do
      association :training
      association :proficient_project
      level {"Beginner"}
    end

    trait :basic_training do
      association :training
      association :proficient_project
      level {"Beginner"}
    end

    trait :laser_cutting do
      association :training
      association :proficient_project
      level {"Intermediate"}
    end

    trait :arduino do
      association :training
      association :proficient_project
      level {"Advanced"}
    end
  end
end
