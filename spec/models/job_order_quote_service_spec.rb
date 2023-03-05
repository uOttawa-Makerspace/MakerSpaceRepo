require "rails_helper"

RSpec.describe JobOrderQuoteService, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:job_order_quote).without_validating_presence }
      it { should belong_to(:job_service).without_validating_presence }
    end
  end

  describe "methods" do
    context "#cost" do
      it "should have the right cost" do
        job_order_quote_service = create(:job_order_quote_service)
        job_order_quote_service.update(per_unit: 2, quantity: 2)
        expect(job_order_quote_service.cost).to eq(4.00)
      end
    end
  end
end
