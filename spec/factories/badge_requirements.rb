require 'faker'

FactoryBot.define do

  factory :badge_requirement do

    trait :three_d_printing do
      badge_template_id { 1 }
    end

    trait :laser_cutting do
      badge_template_id { 2 }
    end

    trait :arduino do
      badge_template_id { 3 }
    end

  end

end






