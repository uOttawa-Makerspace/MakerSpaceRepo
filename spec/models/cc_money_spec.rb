require 'rails_helper'

RSpec.describe CcMoney, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:volunteer_task) }
      it { should belong_to(:proficient_project) }
      it { should belong_to(:order) }
      it { should belong_to(:discount_code) }
    end
  end

  describe 'Methods' do
    context '#create_cc_money_from_approval' do
      it 'cc money should be created if a volunteer task is approved' do
        volunteer = create(:user, :volunteer)
        volunteer_task = create(:volunteer_task)
        cc_money = CcMoney.create_cc_money_from_approval(volunteer_task.id, volunteer.id, 15)
        expect(CcMoney.find(cc_money.id).cc).to eq(15)
        expect(CcMoney.find(cc_money.id).user).to eq(volunteer)
        expect(CcMoney.find(cc_money.id).volunteer_task).to eq(volunteer_task)
      end
    end

    context '#make_new_payment' do
      it 'cc money should be created (with negative cc) after a payment' do
        user = create(:user, :regular_user)
        cc_money = CcMoney.make_new_payment(user, 13)
        expect(CcMoney.find(cc_money.id).cc).to eq(-13)
        expect(CcMoney.find(cc_money.id).user).to eq(user)
      end

      it 'cc money should be created (with negative cc) after a payment' do
        user = create(:user, :regular_user)
        cc_money = CcMoney.make_new_payment(user, -17)
        expect(CcMoney.find(cc_money.id).cc).to eq(-17)
        expect(CcMoney.find(cc_money.id).user).to eq(user)
      end
    end
  end
end
