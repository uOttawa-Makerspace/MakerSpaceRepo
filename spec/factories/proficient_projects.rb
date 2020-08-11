FactoryBot.define do
  factory :proficient_project do

    association :training
    association :badge_template

    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
    level { "Beginner" }
    cc { 10 }
    proficient { true }

    trait :with_files do
      after(:create) do |pp|
        RepoFile.create(proficient_project_id: pp.id, file: fixture_file_upload(Rails.root.join('spec/support/assets', 'RepoFile1.pdf'), 'application/pdf'))
        Photo.create(proficient_project_id: pp.id, image: fixture_file_upload(Rails.root.join('spec/support/assets', 'avatar.png'), 'image/png'))
      end
    end

    trait :broken do
      title { "" }
    end

    trait :intermediate do
      level { "Intermediate" }
    end

    trait :advanced do
      level { "Advanced" }
    end

    trait :not_proficient do
      proficient { false }
    end

    trait :with_badge do
      association :badge_template, :arduino
    end

    trait :with_badge_requirements do
      after :create do |pp|
        create(:badge_template, :'3d_printing_no_id')
        create(:badge_template, :laser_cutting_no_id)
        BadgeRequirement.create(proficient_project_id: pp.id, badge_template_id: BadgeTemplate.find_by_badge_name('Beginner - 3D printing || Débutant - Impression 3D').id)
        BadgeRequirement.create(proficient_project_id: pp.id, badge_template_id: BadgeTemplate.find_by_badge_name('Beginner Laser cutting || Beginner - Laser cutting').id)
      end
    end

    factory :proficient_project_with_project_kits do
      transient do
        project_kit_count { 3 }
      end
      after(:create) do |proficient_project, evaluator|
        create_list(:project_kit, evaluator.project_kit_count, proficient_project: proficient_project)
      end
    end

  end
end
