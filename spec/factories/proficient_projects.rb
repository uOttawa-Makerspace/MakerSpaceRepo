FactoryBot.define do
  factory :proficient_project do

    association :training

    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
    level { "Beginner" }
    cc { 10 }
    proficient { true }

    trait :intermediate do
      level { "Intermediate" }
    end

    trait :advanced do
      level { "Advanced" }
    end

    trait :not_proficient do
      proficient { false }
    end

    trait :with_badge_requirements do
      after :create do |pp|
        create(:badge_template, :'3d_printing')
        create(:badge_template, :laser_cutting)
        BadgeRequirement.create(proficient_project_id: pp.id, badge_template_id: BadgeTemplate.find_by_badge_name('Beginner - 3D printing || Débutant - Impression 3D'))
        BadgeRequirement.create(proficient_project_id: pp.id, badge_template_id: BadgeTemplate.find_by_badge_name('Beginner Laser cutting || Beginner - Laser cutting'))
      end
    end

  end
end
