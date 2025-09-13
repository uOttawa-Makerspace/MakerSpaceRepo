#!/usr/bin/env ruby

FactoryBot.define do
  factory :locker do
    specifier { Faker::Alphanumeric.alphanumeric }
    available { true }
  end
end
