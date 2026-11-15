# frozen_string_literal: true

# One row of the payments ledger: a payment a provider reported, or the reversal of one (which points at the
# payment it reverses and carries its provider_ref). Append-only: a saved entry is read-only here, and a
# database trigger refuses every update and delete. A correction is a new entry.
class PaymentLedgerEntry < ApplicationRecord
  belongs_to :reversed_entry, class_name: "PaymentLedgerEntry", optional: true

  enum :kind, { payment: "payment", reversal: "reversal" }, validate: true

  validates :provider, :provider_ref, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :reversed_entry, presence: true, if: :reversal?
  validates :reversed_entry, absence: true, if: :payment?
  validates :reversed_entry_id, uniqueness: true, allow_nil: true
  validates :provider_ref, uniqueness: { scope: :provider, conditions: -> { payment } }, if: :payment?

  def readonly?
    persisted? || super
  end
end
