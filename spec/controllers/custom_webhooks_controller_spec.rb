require "rails_helper"

RSpec.describe CustomWebhooksController, type: :controller do
  describe "POST /orders_paid" do
    context "webhook from shopify when user pays an order" do
      it "should mark a locker as paid" do
        locker_rental = create(:locker_rental, :await_payment)
        
        post :orders_paid, params: {
          tags: [LockerRental.draft_order_operating_tag],
          metafields: [{
            namespace: "makerepo",
            key: "locker_db_reference",
            value: locker_rental.id.to_s
          }]
        }
        expect(locker_rental.reload.active?).to eq true
      end

      it "should respond to webhooks with the correct tag" do
        locker = create(:locker_rental, :await_payment)
        
        post :orders_paid, params: {
          tags: ["makerepo_locker"], # Send prod tag to test env
          metafields: [{
            namespace: "makerepo",
            key: "locker_db_reference",
            value: locker.id.to_s
          }]
        }
        expect(locker.reload.active?).to eq false
      end

      it "should update discount code as used (usage count = 1)" do
        discount_code = create(:discount_code)
        
        post :orders_paid, params: {
          discount_codes: [{ code: discount_code.code }]
        }
        expect(discount_code.reload.usage_count).to eq(1)
      end

      it "should increment cc_points after purchase" do
        user = create(:user, :regular_user)
        
        post :orders_paid, params: {
          customer: { email: user.email },
          line_items: [{ product_id: 4_359_597_129_784, quantity: 2 }]
        }
        expect(user.cc_moneys.sum(:cc)).to eq(20)
      end

      it "should send email after not signed_in purchase" do
        post :orders_paid, params: {
          customer: { email: "guest@example.com" }, # Static email, no Faker
          line_items: [{ product_id: 4_359_597_129_784, quantity: 2 }]
        }
        expect(CcMoney.last.linked).to be_falsey
        expect(CcMoney.last.cc).to eq(20)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
      end
    end
  end
end