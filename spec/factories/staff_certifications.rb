FactoryBot.define do
  factory :staff_certification do
    trait :certifications_attached do
      after(:build) do |sc|
        (1..StaffCertification::TOTAL_NUMBER_OF_FILES).each do |i|
          pdf_file =
            fixture_file_upload(
              Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
              "application/pdf"
            )
          sc.send("pdf_file_#{i}").attach(pdf_file)
        end
      end
    end
  end
end
