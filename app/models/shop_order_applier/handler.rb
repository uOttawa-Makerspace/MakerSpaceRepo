# frozen_string_literal: true

class ShopOrderApplier
  # One product's part of applying a stored order (ShopOrderApplier::HANDLERS): `call` runs inside the applier's
  # transaction and reports and refuses through the applier, so a rolled-back attempt reports nothing.
  class Handler
    # The reference kind this handler applies: its key in HANDLERS.
    def self.kind = HANDLERS.key(self)

    # Whether a cash payment (an orders/fulfilled delivery) applies this product.
    def self.takes_cash? = false

    # Whether this handler applies (part of) the payment of `event`: the event is a payment (not a cancellation) and
    # names its kind, and a cash payment only when the handler takes cash.
    def self.applies_to?(event) = !event.cancelled && event.kinds.include?(kind) && (takes_cash? || !event.cash)

    # The makerepo metafield that names this product's record in `hook`, when the handler needs one.
    def self.metafield_key(_hook) = nil

    def initialize(applier, plan)
      @applier = applier
      @plan = plan
    end

    private

    attr_reader :applier, :plan

    def hook = plan.hook

    def email = hook.dig("customer", "email").presence

    # The user the order's customer email names (users.email is case-insensitive), or nil; looked up once. Callers
    # check for a blank email first, since each reports it in its own way.
    def customer
      return @customer if defined?(@customer)

      @customer = User.find_by(email: email)
    end

    # The value of this handler's metafield (resolve_references).
    def reference = plan.metafield(self.class.metafield_key(hook))

    # The lookup that was meant to supply this product's reference was refused.
    def left_unapplied? = plan.left_unapplied?(self.class.kind)
  end
end
