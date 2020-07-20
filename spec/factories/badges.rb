require 'faker'

FactoryBot.define do

  factory :badge do

    trait :'3d_printing' do
      issued_to { Faker::Lorem.word }
      acclaim_badge_id { 'dc2f214f-3c2e-4455-sa72-ba5d523e830f' }
      badge_template_id { 1 }
    end

    trait :laser_cutting do
      issued_to { Faker::Lorem.word }
      acclaim_badge_id { 'dc2f214f-3c2e-4955-sa72-ba5d523e830f' }
      badge_template_id { 2 }
    end

    trait :arduino do
      issued_to { Faker::Lorem.word }
      acclaim_badge_id { 'dc2f214f-3c2e-4495-sa72-ba5d524e830f' }
      badge_template_id { BadgeTemplate.find_by_acclaim_template_id('dc2f214f-3c2e-4495-sa72-ba5d524e830f') }
    end

  end

end







