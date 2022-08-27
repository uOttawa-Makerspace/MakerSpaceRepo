require "rails_helper"

RSpec.describe JobOrderQuote, type: :model do
  describe "Association" do
    context "has_one" do
      it { should have_one(:job_order) }
    end

    context "has_many" do
      it { should have_many(:job_order_quote_options) }
      it { should have_many(:job_order_quote_services) }
    end
  end

  describe "methods" do
    context "#total_price" do
      it "should have the right total_price" do
        job_order_quote = create(:job_order_quote)
        job_order_quote.service_fee = 10
        job_order_quote.job_order_quote_services = [
          create(:job_order_quote_service, per_unit: 7, quantity: 2)
        ]
        job_order_quote.job_order_quote_options = [
          create(:job_order_quote_option, amount: 15)
        ]
        expect(job_order_quote.total_price).to eq(39.0)
      end
    end
  end
end
