# frozen_string_literal: true

# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :badge_template do
    acclaim_template_id 'MyText'
    badge_description 'MyText'
    badge_name 'MyText'
  end
end
