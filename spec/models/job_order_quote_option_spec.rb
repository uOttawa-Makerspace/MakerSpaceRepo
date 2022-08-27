require "rails_helper"

RSpec.describe JobOrderQuoteOption, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:job_order_quote) }
      it { should belong_to(:job_option) }
    end
  end
end
