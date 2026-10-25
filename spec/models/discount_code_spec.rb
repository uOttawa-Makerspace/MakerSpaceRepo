require "rails_helper"

RSpec.describe DiscountCode, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:price_rule).without_validating_presence }
      it { should belong_to(:user).without_validating_presence }
    end
    context "has_many" do
      it { should have_many(:cc_moneys) }
      it "dependent destroy: should destroy cc_moneys if destroyed" do
        discount_code = create(:discount_code_with_cc_moneys)
        expect { discount_code.destroy }.to change { CcMoney.count }.by(
          -discount_code.cc_moneys.count
        )
      end
    end
  end

  describe "Validations" do
    context "presence" do
      it { should validate_presence_of(:shopify_discount_code_id) }
      it { should validate_presence_of(:code) }
    end
  end

  describe "Scopes" do
    before :each do
      create(:discount_code, :used)
      create(:discount_code, :used)
      create(:discount_code, :unused)
      create(:discount_code, :unused)
      create(:discount_code, :unused)
    end

    context "#used_code" do
      it "should return used discount codes" do
        expect(DiscountCode.used_code.count).to eq(2)
      end
    end

    context "#not_used" do
      it "should return unused discount codes" do
        expect(DiscountCode.not_used.count).to eq(3)
      end
    end
  end

  context "Methods" do
    context "#generate_code" do
      it "should be a hex" do
        expect(DiscountCode.generate_code.bytesize).to eq(30)
      end
    end

    context "#code_exist?" do
      it "should be true" do
        discount_code = create(:discount_code, :unused)
        expect(DiscountCode.code_exist?(discount_code.code)).to be_truthy
      end

      it "should be false" do
        code = "123"
        expect(DiscountCode.code_exist?(code)).to be_falsey
      end
    end

    context "#status" do
      it "should be Used" do
        discount_code = create(:discount_code, :used)
        expect(discount_code.status).to eq("Used")
      end

      it "should be Not Used" do
        discount_code = create(:discount_code, :unused)
        expect(discount_code.status).to eq("Not used")
      end
    end
  end

  describe "Methods Shopify" do
    before :each do
      @shopify_price_rule_id = PriceRule.create_price_rule("20$ Coupon", 20)
      @price_rule =
        create(
          :price_rule,
          shopify_price_rule_id: @shopify_price_rule_id,
          value: 20
        )
      @discount_code = create(:discount_code, price_rule: @price_rule)
    end

    after :each do
      PriceRule.delete_price_rule_from_shopify(@shopify_price_rule_id)
    end
  end
end

# ---- Chunk 8 characterization (Shopify REST seam, no network) ----------------
RSpec.describe DiscountCode, "Shopify REST seam" do
  before { block_external_http! }

  it "the Shopify REST calls raise RestResourceNotLoadedError (see D-S32 in price_rule_spec)" do
    code = create(:discount_code)
    expect { code.shopify_api_create_discount_code }
      .to raise_error(ShopifyAPI::Errors::RestResourceNotLoadedError, /ShopifyAPI::DiscountCode/)
    expect { code.delete_discount_code_from_shopify }
      .to raise_error(ShopifyAPI::Errors::RestResourceNotLoadedError)
  end

  it "#status is derived from usage_count and a NULL count reads as 'Used'" do
    expect(build(:discount_code, usage_count: 0).status).to eq("Not used")
    expect(build(:discount_code, usage_count: nil).status).to eq("Used")
    expect(build(:discount_code, usage_count: 3).status).to eq("Used")
  end

  it "generate_code gives a 30-char hex and never an existing code" do
    existing = create(:discount_code, code: "a" * 30)
    code = DiscountCode.generate_code
    expect(code).to match(/\A\h{30}\z/)
    expect(code).not_to eq(existing.code)
  end
end
