# frozen_string_literal: true

module Payments
  # A verified payment notice from a provider, in provider-neutral terms. provider_ref is the provider's key for this
  # unit of work (unique per provider); reference is a Payments::Reference, or nil when the payment names no product
  # the app tracks; amount is a BigDecimal, or nil when the provider sent none or an unreadable one.
  PaymentEvent = Data.define(:provider, :provider_ref, :reference, :amount, :paid_at)
end
