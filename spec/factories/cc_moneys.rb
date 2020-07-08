require 'faker'

FactoryBot.define do

  factory :cc_money do

    trait :hundred do
      cc { 100 }
    end

  end

end





