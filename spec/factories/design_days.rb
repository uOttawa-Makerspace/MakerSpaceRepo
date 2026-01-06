FactoryBot.define do
  factory :design_day do
    day do
      Faker::Date.between(
        from: Time.zone.today - 5.years,
        to: Time.zone.today + 5.years
      )
    end
    is_live { Faker::Boolean.boolean }
    sheet_key { Faker::Alphanumeric.alphanumeric number: 44 }
    show_floorplans { Faker::Boolean.boolean }

    after(:build) do |day|
      day.floorplans.attach(
        io: File.open(Rails.root.join("spec/support/assets/test.png")),
        filename: "floorplan.png",
        content_type: "image/png"
      )
    end
    
    after(:create) do |day|
      create_list(:design_day_schedule, 5, design_day: day, event_for: :student)
      create_list(:design_day_schedule, 5, design_day: day, event_for: :judge)
      day.reload
    end
  end
end
