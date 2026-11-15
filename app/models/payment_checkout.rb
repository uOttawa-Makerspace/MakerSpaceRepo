# frozen_string_literal: true

# One payment request sent to a provider (a Shopify draft order today): who it is for, the term it pays for
# (a locker rental's owned_until date), the provider's id for it, and whether it is open, paid or void.
# A reference has at most one open checkout. Nothing writes these yet beyond the copy from locker rentals.
class PaymentCheckout < ApplicationRecord
  belongs_to :reference, polymorphic: true

  enum :status, { open: "open", paid: "paid", void: "void" }, validate: true

  validates :provider, :provider_id, presence: true
  validates :provider_id, uniqueness: { scope: :provider }
  validates :reference_id, uniqueness: { scope: :reference_type, conditions: -> { open } }, if: :open?
end
