require 'rails_helper'

RSpec.describe JobStatus, type: :model do
  describe 'Association' do

    context "has_many" do
      it { should have_many(:job_order_statuses) }
    end
  end

  describe "Validations" do

    context "name" do
      subject { build :job_status }
      it { should validate_presence_of(:name) }
      it { should validate_uniqueness_of(:name) }
    end

  end
end
