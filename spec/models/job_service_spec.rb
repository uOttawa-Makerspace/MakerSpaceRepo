require 'rails_helper'

RSpec.describe JobService, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:job_service_group) }
    end

    context "has_and_belongs_to_many" do
      it { should have_and_belong_to_many(:job_orders) }
    end
  end

  describe 'Active Storage' do
    context 'file type validation' do
      it 'should be false' do
        job_service = build(:job_service, :with_invalid_files)
        expect(job_service.valid?).to be_falsey
      end

      it 'should be true' do
        job_service = build(:job_service, :with_files)
        expect(job_service.valid?).to be_truthy
      end
    end
  end

  describe "methods" do
    context "name_with_internal_price" do
      it "should return name with internal price" do
        job_service = build(:job_service)
        job_service.name = "Test"
        job_service.internal_price = 10
        job_service.unit = "g"
        expect(job_service.name_with_internal_price).to eq("Test ($10.0/g)")
      end
    end

    context "name_with_external_price" do
      it "should return name with internal price" do
        job_service = build(:job_service)
        job_service.name = "Test"
        job_service.external_price = 15
        job_service.unit = "g"
        expect(job_service.name_with_external_price).to eq("Test ($15.0/g)")
      end
    end
  end
end
