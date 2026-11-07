FactoryBot.define do
  factory :design_day_schedule do
    start { Time.zone.now.beginning_of_day + 9.hours }

    # end is a reserved word in Ruby, hence add_attribute
    add_attribute(:end) { Time.zone.now.beginning_of_day + 10.hours }

    sequence(:ordering) { |n| n }

    design_day

    title_en { Faker::Alphanumeric.alphanumeric number: 12 }
    title_fr { Faker::Alphanumeric.alphanumeric number: 12 }
    event_for { :student }
  end
end
