require 'rails_helper'

RSpec.describe DiscountCode, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:price_rule) }
      it { should belong_to(:user) }
    end
    context 'has_many' do
      it { should have_many(:cc_moneys) }
      it 'dependent destroy: should destroy cc_moneys if destroyed' do
        discount_code = create(:discount_code_with_cc_moneys)
        expect { discount_code.destroy }.to change { CcMoney.count }.by(-discount_code.cc_moneys.count)
      end
    end
  end

  describe 'Validations' do
    context 'presence' do
      it { should validate_presence_of(:shopify_discount_code_id) }
      it { should validate_presence_of(:code) }
    end
  end

  describe 'Scopes' do
    before :all do
      create(:discount_code, :used)
      create(:discount_code, :used)
      create(:discount_code, :unused)
      create(:discount_code, :unused)
      create(:discount_code, :unused)
    end

    context '#used_code' do
      it 'should return used discount codes' do
        expect(DiscountCode.used_code.count).to eq(2)
      end
    end

    context '#not_used' do
      it 'should return unused discount codes' do
        expect(DiscountCode.not_used.count).to eq(3)
      end
    end
  end

  context 'Methods' do
    context '#generate_code' do
      it 'should be a hex' do
        expect(DiscountCode.generate_code.bytesize).to eq(30)
      end
    end

    context '#code_exist?' do
      it 'should be true' do
        discount_code = create(:discount_code, :unused)
        expect(DiscountCode.code_exist?(discount_code.code)).to be_truthy
      end

      it 'should be false' do
        code = "123"
        expect(DiscountCode.code_exist?(code)).to be_falsey
      end
    end

    context '#status' do
      it 'should be Used' do
        discount_code = create(:discount_code, :used)
        expect(discount_code.status).to eq("Used")
      end

      it 'should be Not Used' do
        discount_code = create(:discount_code, :unused)
        expect(discount_code.status).to eq("Not used")
      end
    end
  end
end
