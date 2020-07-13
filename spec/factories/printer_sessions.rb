FactoryBot.define do
  factory :printer_session do

    trait :um2p_session do
      association :user, :regular_user
      printer_id { 2 }
    end

    trait :um3_session do
      association :user, :admin
      printer_id { 3 }
    end

    trait :rpl2_session do
      association :user, :regular_user
      printer_id { 5 }
    end

    trait :dremel_session do
      association :user, :admin
      printer_id { 6 }
    end

  end
end
