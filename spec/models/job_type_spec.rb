require 'rails_helper'

RSpec.describe JobType, type: :model do
  describe 'Association' do
    context "has_many" do
      it { should have_many(:job_service_groups) }
      it { should have_many(:job_orders) }
    end

    context "has_and_belongs_to_many" do
      it { should have_and_belong_to_many(:job_options) }
    end
  end

  describe "Validations" do

    context "name" do
      subject { build :job_type }
      it { should validate_presence_of(:name) }
      it { should validate_uniqueness_of(:name) }
    end

  end
end
