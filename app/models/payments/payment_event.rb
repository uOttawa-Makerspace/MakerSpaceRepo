# frozen_string_literal: true

module Payments
  # A verified payment notice from a provider, in provider-neutral terms. provider_ref is the provider's key for this
  # unit of work (unique per provider; nil when the provider sent no key); references are the Payments::References of
  # every product the payment is for, in Reference::KINDS order (empty when it names none the app tracks); amount is a
  # BigDecimal, or nil when the provider sent none or an unreadable one; cash is true for a payment taken in cash
  # rather than through the provider's checkout; cancelled is true for a notice that the order was cancelled (Shopify's
  # orders/cancelled, which is also how a voided pending payment arrives), not a payment.
  PaymentEvent = Data.define(:provider, :provider_ref, :references, :amount, :paid_at, :cash, :cancelled) do
    def initialize(cancelled: false, **fields) = super

    def kinds = references.map(&:kind)
  end
end
