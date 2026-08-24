# frozen_string_literal: true

FactoryBot.define do
  factory :pi_reader do
    association :space
    sequence(:pi_mac_address) { |n| "00:11:22:33:%02X:%02X" % [(n / 256) % 256, n % 256] }
    pi_location { "Room Location" }
  end
end
