FactoryBot.define do
  factory :training_requirement do
    association :training
    association :proficient_project

    # FIXME: The traits don't really do anything anymore
    trait :"3d_printing" do
      association :training
      association :proficient_project
    end

    trait :basic_training do
      association :training
      association :proficient_project
    end

    trait :laser_cutting do
      association :training
      association :proficient_project
    end

    trait :arduino do
      association :training
      association :proficient_project
    end
  end
end
