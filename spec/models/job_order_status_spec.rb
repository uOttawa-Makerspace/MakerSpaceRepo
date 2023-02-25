require "rails_helper"

RSpec.describe JobOrderStatus, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:job_order).without_validating_presence }
      it { should belong_to(:job_status).without_validating_presence }
    end
  end
end
