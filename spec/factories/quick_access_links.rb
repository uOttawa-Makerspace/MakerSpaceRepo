#!/usr/bin/env ruby

FactoryBot.define do
  factory :quick_access_link do
    trait :root do
      path { '/' }
      name { 'Makerepo' }
    end

    trait :invalid do
      path { 'admin/invalid' }
      name { 'invalid path' }
    end
  end
end
