require 'faker'

FactoryBot.define do

  factory :like do

    association :repository
    association :user, :regular_user

  end
end

