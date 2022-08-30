require "rails_helper"

RSpec.describe JobServiceGroup, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:job_type) }
    end

    context "has_many" do
      it { should have_many(:job_order) }
      it { should have_many(:job_services) }
    end
  end

  describe "Validations" do
    context "name" do
      subject { build :job_service_group }
      it { should validate_presence_of(:name) }
      it { should validate_uniqueness_of(:name) }
    end

    context "job_type_id" do
      subject { build :job_service_group }
      it { should validate_presence_of(:job_type_id) }
    end
  end
end
