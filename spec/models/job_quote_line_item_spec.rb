require "rails_helper"

RSpec.describe JobQuoteLineItem, type: :model do
  describe "Association" do
    it { should belong_to(:job_order) }
  end

  describe "Validations" do
    subject { build(:job_quote_line_item, job_order: create(:job_order)) }

    it { should validate_presence_of(:description) }
    it { should validate_numericality_of(:price).is_greater_than_or_equal_to(0) }
  end

  describe "behaviour" do
    it "allows a 0 price (free add-ons)" do
      order = create(:job_order)
      item = order.job_quote_line_items.create!(description: "Expedited SLA resin", price: 0)
      expect(item.reload.price).to eq(0)
    end

    it "stores exact decimals" do
      order = create(:job_order)
      item = order.job_quote_line_items.create!(description: "Resin", price: "12.35")
      expect(item.reload.price).to eq(BigDecimal("12.35"))
    end

    it "rejects negative prices" do
      order = create(:job_order)
      item = build(:job_quote_line_item, job_order: order, price: -1)
      expect(item).not_to be_valid
    end
  end
end
