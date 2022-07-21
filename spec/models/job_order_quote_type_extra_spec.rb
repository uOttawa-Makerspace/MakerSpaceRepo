require 'rails_helper'

RSpec.describe JobOrderQuoteTypeExtra, type: :model do
  describe 'Association' do
    context "belongs_to" do
      it { should belong_to(:job_order_quote) }
      it { should belong_to(:job_type_extra) }
    end
  end
end
