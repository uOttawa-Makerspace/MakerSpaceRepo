FactoryBot.define do
  factory :membership_tier do
    sequence(:title_en) { |n| "Membership Tier #{n}" }
    sequence(:title_fr) { |n| "Adhésion #{n}" }
    internal_price { 30.0 }
    external_price { 30.0 }
    duration { 30.days.to_i }
    hidden { false }
  end
end