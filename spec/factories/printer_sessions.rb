require 'faker'

FactoryBot.define do
  factory :printer_session do

    trait :um2p_session do
      user_id { 1 }
      printer_id { 2 }
    end

    trait :um3_session do
      user_id { 2 }
      printer_id { 3 }
    end

    trait :rpl2_session do
      user_id { 1 }
      printer_id { 5 }
    end

    trait :dremel_session do
      user_id { 2 }
      printer_id { 6 }
    end

  end
end
