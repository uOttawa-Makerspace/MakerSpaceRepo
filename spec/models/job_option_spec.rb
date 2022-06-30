require 'rails_helper'

RSpec.describe JobOption, type: :model do
  describe 'Association' do
    context "has_many" do
      it { should have_many(:job_order_options) }
      it { should have_many(:job_order_quote_options) }
    end

    context "has_and_belongs_to_many" do
      it { should have_and_belong_to_many(:job_types) }
    end
  end

  describe "Validations" do

    context "name" do
      subject { build :job_option }
      it { should validate_presence_of(:name) }
      it { should validate_uniqueness_of(:name) }
    end

    context "fee" do
      subject { build :job_option }
      it { should validate_presence_of(:fee) }
    end
  end
end
