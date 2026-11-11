# frozen_string_literal: true

# The record of one admin correcting the purchase email of an unclaimed CC Money row. Written by
# CcMoney#correct_purchase_email, never changed or removed afterwards.
class CcMoneyEmailCorrection < ApplicationRecord
  belongs_to :cc_money
  # The admin who made the change, shown even after that account is soft-deleted.
  belongs_to :admin, -> { including_deleted }, class_name: "User", inverse_of: false

  # Append-only by convention: a saved correction cannot be updated or destroyed through ActiveRecord, but
  # delete_all and raw SQL bypass this.
  def readonly? = persisted? || super
end
