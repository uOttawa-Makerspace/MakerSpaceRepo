# frozen_string_literal: true

# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :print_order do
    userid ''
    approved false
    printed false
  end
end
