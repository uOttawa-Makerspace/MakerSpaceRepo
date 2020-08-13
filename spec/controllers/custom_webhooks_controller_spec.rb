require 'rails_helper'

RSpec.describe CustomWebhooksController, type: :controller do
  describe "POST /orders_paid" do
    context 'webhook from shopify when user pays an order' do
      it 'should update discount code as used (usage count = 1)' do
        discount_code = create(:discount_code)
        post :orders_paid, params: { 'discount_codes' => [ {'code' => discount_code.code } ] }
        expect(DiscountCode.find_by(id: discount_code.id).usage_count).to eq(1)
      end

      it 'should increment cc_points after purchase' do
        user = create(:user, :regular_user)
        post :orders_paid, params: { 'customer' => { 'email' => user.email }, 'line_items' => [ {'product_id' => 4359597129784, 'quantity' => 2 } ] }
        expect(user.cc_moneys.count).to eq(1)
        expect(user.cc_moneys.sum(:cc)).to eq(20)
      end

      it 'should send email after not signed_in purchase' do
        post :orders_paid, params: { 'customer' => { 'email' => Faker::Internet.email }, 'line_items' => [ {'product_id' => 4359597129784, 'quantity' => 2 } ] }
        expect(CcMoney.last.linked).to be_falsey
        expect(CcMoney.last.cc).to eq(20)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
      end

    end
  end
end

