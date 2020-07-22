FactoryBot.define do
  factory :photo do
    image { FilesTestHelper.png }

    trait :in_repository do
      association :repository
    end

    trait :in_proficient_project do
      association :proficient_project
    end

    trait :with_invalid_image do
      image { FilesTestHelper.stl }
    end
  end
end

# create_table "photos", id: :serial, force: :cascade do |t|
#   t.integer "repository_id"
#   t.string "image_file_name"
#   t.string "image_content_type"
#   t.integer "image_file_size"
#   t.datetime "image_updated_at"
#   t.integer "height"
#   t.integer "width"
#   t.integer "proficient_project_id"
# end
