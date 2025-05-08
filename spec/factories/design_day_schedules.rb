FactoryBot.define do
  factory :design_day_schedule do
    start do
      Faker::Time.between from: Time.zone.now.beginning_of_day, to: Time.zone.now.end_of_day
    end

    # FIXME: end is a reserved keyword
    add_attribute(:end) do
      Faker::Time.between from: Time.zone.now.beginning_of_day, to: Time.zone.now.end_of_day
    end

    ordering { Faker::Number.between from: 0, to: 20 }

    design_day

    title_en { Faker::Alphanumeric.alphanumeric number: 12 }
    title_fr { Faker::Alphanumeric.alphanumeric number: 12 }
    event_for { DesignDaySchedule.event_fors.values.sample }
  end
end
