# frozen_string_literal: true

class ShopOrderApplier
  # One product's part of applying a stored order (ShopOrderApplier::HANDLERS): `call` runs inside the applier's
  # transaction and reports and refuses through the applier, so a rolled-back attempt reports nothing.
  class Handler
    # The product this handler applies, as a refused lookup names it ("left unapplied: locker").
    PRODUCT = nil

    # Whether a cash payment (an orders/fulfilled delivery) applies this product.
    def self.takes_cash? = false

    # The makerepo metafield that names this product's record in `hook`, when the handler needs one.
    def self.reference_key(_hook) = nil

    def initialize(applier, plan)
      @applier = applier
      @plan = plan
    end

    private

    attr_reader :applier, :plan

    def hook = plan.hook

    def email = hook.dig("customer", "email").presence
  end
end
