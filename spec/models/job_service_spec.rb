require "rails_helper"

RSpec.describe JobService, type: :model do
  describe "Associations" do
    it { should belong_to(:job_service_group).without_validating_presence }
  end

  describe "Active Storage" do
    context "file type validation" do
      it "is invalid with incorrect file types" do
        job_service = build(:job_service, :with_invalid_files)
        expect(job_service).not_to be_valid
      end

      it "is valid with correct file types" do
        job_service = build(:job_service, :with_files)
        expect(job_service).to be_valid
      end
    end
  end
end
