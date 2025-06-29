FactoryBot.define do
  factory :training_requirement do
    trait :"3d_printing" do
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
