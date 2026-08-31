# frozen_string_literal: true

require "rails_helper"
include ShopifyConcern

RSpec.describe PriceRule, type: :model do
  describe "Association" do
    context "has_many" do
      it { should have_many(:discount_codes) }
      it "dependent destroy: should destroy cc_moneys if destroyed" do
        price_rule = create(:price_rule_with_discount_codes)
        expect { price_rule.destroy }.to change { DiscountCode.count }.by(
          -price_rule.discount_codes.count
        )
      end
    end
  end

  describe "Validations" do
    context "presence" do
      it { should validate_presence_of(:shopify_price_rule_id) }
      it { should validate_presence_of(:title) }
      it { should validate_presence_of(:value) }
      it { should validate_presence_of(:cc) }
    end
  end

  describe "Methods" do
    context "#has_discount_codes?" do
      let(:price_rule) { create(:price_rule_with_discount_codes) }

      it "should return true" do
        expect(price_rule.has_discount_codes?).to eq(true)
      end

      it "should return false" do
        price_rule.discount_codes.destroy_all
        expect(price_rule.has_discount_codes?).to eq(false)
      end
    end
  end
end
