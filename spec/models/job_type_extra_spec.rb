require "rails_helper"

RSpec.describe JobTypeExtra, type: :model do
  describe "Association" do
    context "has_many" do
      it { should have_many(:job_order_quote_type_extras) }
    end

    context "belong_to" do
      it { should belong_to(:job_type).without_validating_presence }
    end
  end

  describe "Validations" do
    context "name" do
      subject { build :job_type_extra }
      it { should validate_presence_of(:name) }
    end
  end
end
