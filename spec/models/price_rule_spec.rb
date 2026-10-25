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

# ---- Chunk 8 characterization: the Shopify REST seam ------------------------
RSpec.describe PriceRule, "Shopify REST seam" do
  before { block_external_http! }

  # WART(D-S32): ShopifyAPI::Context.setup is never called (only the unused ShopifyCartConcern does it), so the REST resource classes ShopifyAPI::PriceRule / ::DiscountCode are not loaded in ANY environment; every price-rule Shopify call raises before reaching the network
  it "every Shopify price-rule call raises RestResourceNotLoadedError (REST resources are not loaded)" do
    expect { PriceRule.create_price_rule("10$ coupon", 10) }
      .to raise_error(ShopifyAPI::Errors::RestResourceNotLoadedError, /ShopifyAPI::PriceRule/)
    expect { PriceRule.update_price_rule("55", "T", 3) }
      .to raise_error(ShopifyAPI::Errors::RestResourceNotLoadedError)
    expect { PriceRule.delete_price_rule_from_shopify("55") }
      .to raise_error(ShopifyAPI::Errors::RestResourceNotLoadedError)
  end

  it "stores shopify_price_rule_id as a string" do
    rule = create(:price_rule, shopify_price_rule_id: 123)
    expect(rule.reload.shopify_price_rule_id).to eq("123")
  end
end
