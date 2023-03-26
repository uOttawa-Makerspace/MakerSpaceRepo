require "rails_helper"

RSpec.describe JobOrder, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:job_type).without_validating_presence }
      it { should belong_to(:job_service_group).without_validating_presence }
      it { should belong_to(:job_order_quote).without_validating_presence }
    end

    context "belongs_to" do
      it { should have_many(:job_order_options) }
      it { should have_many(:job_order_statuses) }
    end

    context "has_and_belongs_to_many" do
      it { should have_and_belong_to_many(:job_services) }
    end
  end

  describe "Active Storage" do
    context "file type validation" do
      it "should be false" do
        job_order = build(:job_order, :with_invalid_user_files)
        expect(job_order.valid?).to be_falsey
      end

      it "should be true" do
        job_order = build(:job_order, :with_user_files)
        expect(job_order.valid?).to be_truthy
      end
    end

    context "staff_files type validation" do
      it "should be false" do
        job_order = build(:job_order, :with_invalid_staff_files)
        expect(job_order.valid?).to be_falsey
      end

      it "should be true" do
        job_order = build(:job_order, :with_staff_files)
        expect(job_order.valid?).to be_truthy
      end
    end
  end
end
