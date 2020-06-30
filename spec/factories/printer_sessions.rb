require 'faker'

FactoryBot.define do
  factory :printer_session do

    trait :um2p_session do
      user_id { 1 }
      printer_id { 2 }
    end

  end
end
