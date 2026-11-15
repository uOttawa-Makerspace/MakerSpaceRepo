# frozen_string_literal: true

require "rails_helper"

# The handler registry: which handlers apply a PaymentEvent (what applying does: apply_processed_order_job_spec.rb and
# shop_order_routing_spec.rb).
RSpec.describe ShopOrderApplier do
  def event(*kinds, cash: false)
    Payments::PaymentEvent.new(provider: "shopify", provider_ref: "1", references: kinds.map { |k| Payments::Reference.new(kind: k) },
                               amount: nil, paid_at: Time.current, cash: cash)
  end

  describe ".handlers_for" do
    it "maps each kind to its handler, in the registry's order whatever the order of the references" do
      expect(described_class.handlers_for(event("cc_money", "membership", "locker")))
        .to eq([described_class::LockerHandler, described_class::MembershipHandler, described_class::CcMoneyHandler])
    end

    it "has no handler for job orders or an event that names nothing" do
      expect(described_class.handlers_for(event("job_order"))).to eq([])
      expect(described_class.handlers_for(event)).to eq([])
    end

    it "applies a cash payment only with a handler that takes cash" do
      expect(described_class.handlers_for(event("locker", "membership", "cc_money", cash: true))).to eq([described_class::LockerHandler])
      expect(described_class.handlers_for(event("membership", cash: true))).to eq([])
    end

    it "has a handler for every kind but job orders" do
      expect(described_class::HANDLERS.keys).to eq(Payments::Reference::KINDS - ["job_order"])
    end
  end

  describe "a handler" do
    it "knows its kind from the registry" do
      expect(described_class::HANDLERS.values.map(&:kind)).to eq(described_class::HANDLERS.keys)
    end
  end

  it "applies an order whose metafield lookup did not run as one without a reference" do
    rental = create(:locker_rental, :await_payment)
    order, = ProcessedOrder.receive!(provider: "shopify", order_id: 7501, topic: "orders/paid",
                                     payload: { "id" => 7501, "tags" => [LockerRental.draft_order_operating_tag] })
    allow_any_instance_of(described_class).to receive(:resolve_references)
    reports = []
    allow(Rails.error).to receive(:report) { |error, **| reports << error.class }
    described_class.new(order).call
    expect([order.reload.status, rental.reload.state]).to eq(%w[applied await_payment])
    expect(reports).to eq([described_class::LockerOrderWithoutReference])
  end
end
