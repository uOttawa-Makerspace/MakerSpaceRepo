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

  describe "Methods" do
    describe "#name_with_internal_price" do
      it "returns the name with internal price and unit" do
        job_service = build(:job_service, name: "Test", internal_price: 10, unit: "g")
        expect(job_service.name_with_internal_price).to eq("Test ($10.0/g)")
      end
    end

    describe "#name_with_external_price" do
      it "returns the name with external price and unit" do
        job_service = build(:job_service, name: "Test", external_price: 15, unit: "g")
        expect(job_service.name_with_external_price).to eq("Test ($15.0/g)")
      end
    end
  end
end
