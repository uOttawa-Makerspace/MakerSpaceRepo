# frozen_string_literal: true

# One row of the payments ledger: a payment a provider reported, or the reversal of one, which points at the
# payment it reverses and carries its provider and provider_ref (the database enforces this too). Append-only: a
# saved entry is read-only here, and a database trigger refuses every update and delete. A correction is a new
# entry.
class PaymentLedgerEntry < ApplicationRecord
  belongs_to :reversed_entry, class_name: "PaymentLedgerEntry", optional: true

  enum :kind, { payment: "payment", reversal: "reversal" }, validate: true

  validates :provider, :provider_ref, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :reversed_entry, presence: true, if: :reversal?
  validates :reversed_entry, absence: true, if: :payment?
  validates :reversed_entry_id, uniqueness: true, allow_nil: true
  validates :provider_ref, uniqueness: { scope: :provider, conditions: -> { payment } }, if: :payment?
  validate :reverses_a_matching_payment, if: :reversal?

  def readonly?
    persisted? || super
  end

  private

  # A reversal points at a payment (not another reversal) with its own provider and provider_ref.
  def reverses_a_matching_payment
    target = reversed_entry
    return if target.nil? || (target.payment? && [target.provider, target.provider_ref] == [provider, provider_ref])

    errors.add(:reversed_entry, :invalid)
  end
end
