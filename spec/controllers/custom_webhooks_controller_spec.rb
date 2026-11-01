require "rails_helper"

RSpec.describe CustomWebhooksController, type: :controller do
  # Order matters: the secret guard (503) and the header guard (401) must run before the gem's
  # HMAC check, which raises on a missing header. Declared at load time, not per request.
  it "runs the secret guard, then the header guard, then the gem's HMAC check, as plain (unconditional) callbacks" do
    callbacks = described_class._process_action_callbacks.select { |c| c.kind == :before }
    names = callbacks.map(&:filter) & %i[require_webhook_secret! require_hmac_header! verify_request]
    expect(names).to eq(%i[require_webhook_secret! require_hmac_header! verify_request])
    guards = callbacks.select { |c| %i[require_webhook_secret! require_hmac_header!].include?(c.filter) }
    expect(guards.map { |c| c.instance_variable_get(:@if) }).to all(be_empty)
    expect(guards.map { |c| c.instance_variable_get(:@unless) }).to all(be_empty)
  end

  describe "POST /orders_paid" do
    context "webhook from shopify when user pays an order" do
      it "should mark a locker as paid" do
        locker_rental = create(:locker_rental, :await_payment)
        
        signed_controller_orders_paid({
          id: 820_982_911_946_154_508,
          tags: [LockerRental.draft_order_operating_tag],
          metafields: [{
            namespace: "makerepo",
            key: "locker_db_reference",
            value: locker_rental.id.to_s
          }]
        })
        expect(locker_rental.reload.active?).to eq true
      end

      it "should respond to webhooks with the correct tag" do
        locker = create(:locker_rental, :await_payment)
        
        signed_controller_orders_paid({
          tags: ["makerepo_locker"], # Send prod tag to test env
          metafields: [{
            namespace: "makerepo",
            key: "locker_db_reference",
            value: locker.id.to_s
          }]
        })
        expect(locker.reload.active?).to eq false
      end

      it "should increment cc_points after purchase" do
        user = create(:user, :regular_user)
        
        signed_controller_orders_paid({
          customer: { email: user.email },
          line_items: [{ product_id: 4_359_597_129_784, quantity: 2 }]
        })
        expect(user.cc_moneys.sum(:cc)).to eq(20)
      end

      it "should send email after not signed_in purchase" do
        signed_controller_orders_paid({
          customer: { email: "guest@example.com" }, # Static email, no Faker
          line_items: [{ product_id: 4_359_597_129_784, quantity: 2 }]
        })
        expect(CcMoney.last.linked).to be_falsey
        expect(CcMoney.last.cc).to eq(20)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
      end
    end
  end
end