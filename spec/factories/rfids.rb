# frozen_string_literal: true

FactoryBot.define do
  factory :rfid do
    association :user, :regular_user
    sequence(:card_number) { |n| "RFID%010d" % n }
    sequence(:mac_address) { |n| "00:11:22:33:%02X:%02X" % [(n / 256) % 256, n % 256] }
  end
end
