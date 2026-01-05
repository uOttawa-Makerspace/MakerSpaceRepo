require "rails_helper"

RSpec.describe CustomWebhooksController, type: :controller do
  describe "POST /orders_paid" do
    # Stub Shopify verification globally for all tests
    before do
      allow(controller).to receive(:verify_shopify_webhook).and_return(true)
    end

    it "marks locker as paid and responds only to correct tags" do
      locker_rental = create(:locker_rental, :await_payment)
      incorrect_locker = create(:locker_rental, :await_payment)
      
      # Test correct tag
      post :orders_paid, params: {
        tags: [LockerRental.draft_order_operating_tag],
        metafields: [{
          namespace: "makerepo",
          key: "locker_db_reference",
          value: locker_rental.id.to_s
        }]
      }
      expect(locker_rental.reload.active?).to eq true
      
      # Test incorrect tag in same test
      post :orders_paid, params: {
        tags: ["makerepo_locker"],
        metafields: [{
          namespace: "makerepo",
          key: "locker_db_reference",
          value: incorrect_locker.id.to_s
        }]
      }
      expect(incorrect_locker.reload.active?).to eq false
    end

    it "updates discount code and handles CC points" do
      discount_code = create(:discount_code)
      user = create(:user, :regular_user)
      
      # Combine discount code test with CC points test
      post :orders_paid, params: {
        discount_codes: [{ code: discount_code.code }],
        customer: { email: user.email },
        line_items: [{ product_id: 4_359_597_129_784, quantity: 2 }]
      }
      
      expect(discount_code.reload.usage_count).to eq(1)
      expect(user.cc_moneys.sum(:cc)).to eq(20)
    end

    it "sends email for non-signed-in purchase" do
      post :orders_paid, params: {
        customer: { email: "guest@example.com" }, # Use static email, no Faker
        line_items: [{ product_id: 4_359_597_129_784, quantity: 2 }]
      }
      
      expect(CcMoney.last.linked).to be_falsey
      expect(CcMoney.last.cc).to eq(20)
      expect(ActionMailer::Base.deliveries.count).to eq(1)
    end
  end
end