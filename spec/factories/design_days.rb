FactoryBot.define do
  factory :design_day do
    day { Date.new(2026, 3, 14) }
    is_live { true }
    sheet_key { Faker::Alphanumeric.alphanumeric number: 44 }
    show_floorplans { true }

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
