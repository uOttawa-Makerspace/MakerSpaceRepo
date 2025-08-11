FactoryBot.define do
  factory :training_requirement do
    association :training

    # FIXME: The traits don't really do anything anymore
    trait :"3d_printing" do
      association :training
    end

    trait :basic_training do
      association :training
    end

    trait :laser_cutting do
      association :training
    end

    trait :arduino do
      association :training
    end
  end
end
