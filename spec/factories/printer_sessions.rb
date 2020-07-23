FactoryBot.define do
  factory :printer_session do

    trait :um2p_session do
      association :user, :regular_user
      association :printer, :UM2P_02
    end

    trait :um3_session do
      association :user, :admin
      association :printer, :UM3_01
    end

    trait :rpl2_session do
      association :user, :regular_user
      association :printer, :RPL2_01
    end

    trait :dremel_session do
      association :user, :admin
      association :printer, :dremel_10_17
    end

  end
end
