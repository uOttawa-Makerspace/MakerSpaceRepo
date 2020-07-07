require 'rails_helper'

RSpec.describe DiscountCode, type: :model do

  describe 'validation' do

    context 'Validation of shopify discount rule id' do
      it 'should be false' do
        discount = build(:discount_code, :missing_shopify_discount_code_id)
        expect(discount.valid?).to be_falsey
      end
    end

    context 'Validation of the code' do
      it 'should be false' do
        discount_code = build :discount_code, :missing_code
        expect(discount_code.valid?).to be_falsey
      end
    end

  end

  describe 'scopes' do

    context 'Scope get used' do
      it 'should return used code' do
        create(:user, :regular_user)
        create(:price_rule, :working_print_rule_with_id)
        create(:discount_code, :used_discount_code)
        create(:discount_code, :used_discount_code)
        expect(DiscountCode.all.used_code.count).to eq(2)
      end
    end

    context 'Scope get not used' do
      it 'should return unused codes' do
        create(:user, :regular_user)
        create(:price_rule, :working_print_rule_with_id)
        create(:discount_code, :unused_code)
        create(:discount_code, :unused_code)
        expect(DiscountCode.all.not_used.count).to eq(2)
      end
    end

  end

  context 'methods' do

    context 'generate code' do

      it 'should be a hex' do
        expect(DiscountCode.generate_code.bytesize).to eq(30)
      end

    end

    context 'code exists' do

      it 'should be true' do
        code = DiscountCode.generate_code
        create(:price_rule, :working_print_rule_with_id)
        create(:discount_code, :unused_code, code: code)
        expect(DiscountCode.code_exist?(code)).to be_truthy
      end

      it 'should be false' do
        code = "32532n32h35h32h5"
        expect(DiscountCode.code_exist?(code)).to be_falsey
      end

    end

    context 'status' do

      it 'should be Used' do
        create(:price_rule, :working_print_rule_with_id)
        code = create(:discount_code, :used_discount_code)
        expect(code.status).to eq("Used")
      end

      it 'should be Not Used' do
        create(:price_rule, :working_print_rule_with_id)
        code = create(:discount_code, :unused_code)
        expect(code.status).to eq("Not used")
      end

    end

  end

end
