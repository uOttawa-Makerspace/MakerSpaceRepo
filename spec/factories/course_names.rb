# frozen_string_literal: true

FactoryBot.define do
  factory :course_name do
    sequence(:name) { |n| "Course #{n}" }
  end
end