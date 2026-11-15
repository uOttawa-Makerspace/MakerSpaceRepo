# frozen_string_literal: true

require "rails_helper"

# The handler registry: which handlers apply a PaymentEvent (what applying does: apply_processed_order_job_spec.rb and
# shop_order_routing_spec.rb).
RSpec.describe ShopOrderApplier do
  def event(*kinds, cash: false, cancelled: false)
    references = kinds.map { |k| Payments::Reference.new(kind: k) }
    Payments::PaymentEvent.new(provider: "shopify", provider_ref: "1", references: references,
                               amount: nil, paid_at: Time.current, cash: cash, cancelled: cancelled)
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
      expect(described_class.handlers_for(event("locker", "membership", "cc_money", cash: true)))
        .to eq([described_class::LockerHandler])
      expect(described_class.handlers_for(event("membership", cash: true))).to eq([])
    end

    it "has no handler for a cancellation, whatever it names" do
      expect(described_class.handlers_for(event("locker", "membership", "cc_money", cancelled: true))).to eq([])
    end

    it "has a handler for every kind but job orders" do
      expect(described_class::HANDLERS.keys).to eq(Payments::Reference::KINDS - ["job_order"])
    end
  end

  describe ".stores?" do
    it "stores a payment some handler applies, and no other" do
      expect(described_class.stores?(event("membership"))).to be(true)
      expect(described_class.stores?(event("job_order"))).to be(false)
      expect(described_class.stores?(event("membership", cash: true))).to be(false)
    end

    it "stores the cancellation of an order for any tracked product, and of no other order" do
      %w[locker membership cc_money job_order].each do |kind|
        expect(described_class.stores?(event(kind, cancelled: true))).to be(true), kind
      end
      expect(described_class.stores?(event("locker", "membership", cancelled: true))).to be(true)
      expect(described_class.stores?(event(cancelled: true))).to be(false)
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
