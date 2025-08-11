require "rails_helper"

RSpec.describe JobOrder, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
    end

    context "belongs_to" do
      it { should have_many(:job_tasks).dependent(:destroy) }
      it { should have_many(:job_order_statuses) }
    end
  end
end
