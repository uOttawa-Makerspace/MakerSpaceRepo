require "rails_helper"

RSpec.describe JobOrderQuoteOption, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:job_order_quote).without_validating_presence }
      it { should belong_to(:job_option).without_validating_presence }
    end
  end
end
