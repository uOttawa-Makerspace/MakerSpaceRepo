require 'rails_helper'
include ShopifyConcern

RSpec.describe PriceRule, type: :model do

  describe 'Validation' do

    context 'Validation of shopify price rule id' do
      it 'should be false' do
        price_rule = build :price_rule,  :missing_shopify_price_rule_id
        expect(price_rule.valid?).to be_falsey
      end
    end

    context 'Validation of the title' do
      it 'should be false' do
        price_rule = build :price_rule,  :missing_title
        expect(price_rule.valid?).to be_falsey
      end
    end

    context 'Validation of the value' do
      it 'should be false' do
        price_rule = build :price_rule,  :missing_value
        expect(price_rule.valid?).to be_falsey
      end
    end

    context 'Validation of the cc' do
      it 'should be false' do
        price_rule = build :price_rule,  :missing_cc
        expect(price_rule.valid?).to be_falsey
      end
    end

    context 'Validation of everything together' do
      it 'should be true' do
        price_rule = build :price_rule,  :working_print_rule
        expect(price_rule.valid?).to be_truthy
      end
    end

  end

  describe 'model methods' do

    context 'create price rule' do
      it 'should be an integer' do
        expect(PriceRule.create_price_rule("5$ Coupon", 5)).to be_a_kind_of(Integer)
      end
    end

    context 'delete price rule' do
      start_shopify_session

      it 'should be deleting the price rule' do
        price_rule = PriceRule.create_price_rule("5$ Coupon", 5)
        PriceRule.delete_price_rule_from_shopify(price_rule)
        expect {
          ShopifyAPI::PriceRule.find(price_rule)
        }.to raise_error(ActiveResource::ResourceNotFound)
      end
    end

    context 'update price rule' do
      start_shopify_session

      it 'should update the price rule' do
        price_rule = PriceRule.create_price_rule("5$ Coupon", 5)
        PriceRule.update_price_rule(price_rule, "6$ Coupon", 6)
        shopify_price_rule = ShopifyAPI::PriceRule.find(price_rule)
        expect(shopify_price_rule.value).to eq("-6.0")
        expect(shopify_price_rule.title).to eq("6$ Coupon")
      end
    end

  end

end
