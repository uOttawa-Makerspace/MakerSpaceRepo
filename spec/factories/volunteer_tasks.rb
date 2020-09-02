FactoryBot.define do
  factory :volunteer_task do
    association :space
    title { Faker::Lorem.word }
    description { Faker::Lorem.paragraph }
    status { "open" }
    joins { 1 }
    category { "Events" }
    cc { 10 }
    hours { 5.00 }

    trait :with_certifications do
      after :create do |task|
        training1 = create(:training)
        training2 = create(:training)
        RequireTraining.create(volunteer_task_id: task.id, training_id: training1.id)
        RequireTraining.create(volunteer_task_id: task.id, training_id: training2.id)
      end
    end
  end
end






