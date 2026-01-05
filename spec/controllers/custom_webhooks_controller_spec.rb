require "rails_helper"

RSpec.describe CustomWebhooksController, type: :controller do
  describe "POST /orders_paid" do
    # Create expensive objects ONCE for all tests
    before(:all) do
      @rented_by_user = create(:user)
      @decided_by_user = create(:user)
      @locker1 = create(:locker)
      @locker2 = create(:locker)
      
      # Manually create locker rentals to share users
      @locker_rental = LockerRental.create!(
        rented_by: @rented_by_user,
        decided_by: @decided_by_user,
        locker: @locker1,
        state: :await_payment,
        requested_as: 'general',
        owned_until: 30.days.from_now
      )
      
      @incorrect_locker = LockerRental.create!(
        rented_by: @rented_by_user,
        decided_by: @decided_by_user,
        locker: @locker2,
        state: :await_payment,
        requested_as: 'general',
        owned_until: 30.days.from_now
      )
      
      @discount_code = create(:discount_code)
      @user = create(:user, :regular_user)
    end

    after(:all) do
      DatabaseCleaner.clean_with(:truncation)
    end

    # Reset state before each test
    before(:each) do
      @locker_rental.update_column(:state, 'await_payment') # Use update_column to skip callbacks
      @incorrect_locker.update_column(:state, 'await_payment')
      @discount_code.update_column(:usage_count, 0)
      ActionMailer::Base.deliveries.clear
    end

    it "marks locker as paid" do
      post :orders_paid, params: {
        tags: [LockerRental.draft_order_operating_tag],
        metafields: [{
          namespace: "makerepo",
          key: "locker_db_reference",
          value: @locker_rental.id.to_s
        }]
      }
      expect(@locker_rental.reload.active?).to eq true
    end

    it "responds only to correct tags" do
      post :orders_paid, params: {
        tags: ["makerepo_locker"],
        metafields: [{
          namespace: "makerepo",
          key: "locker_db_reference",
          value: @incorrect_locker.id.to_s
        }]
      }
      expect(@incorrect_locker.reload.active?).to eq false
    end

    it "updates discount code as used" do
      post :orders_paid, params: {
        discount_codes: [{ code: @discount_code.code }]
      }
      expect(@discount_code.reload.usage_count).to eq(1)
    end

    it "increments cc_points after purchase" do
      post :orders_paid, params: {
        customer: { email: @user.email },
        line_items: [{ product_id: 4_359_597_129_784, quantity: 2 }]
      }
      expect(@user.cc_moneys.sum(:cc)).to eq(20)
    end

    it "sends email after non-signed-in purchase" do
      post :orders_paid, params: {
        customer: { email: "guest@example.com" },
        line_items: [{ product_id: 4_359_597_129_784, quantity: 2 }]
      }
      
      expect(CcMoney.last.linked).to be_falsey
      expect(CcMoney.last.cc).to eq(20)
      expect(ActionMailer::Base.deliveries.count).to eq(1)
    end
  end
end