# frozen_string_literal: true

# The record of one admin resending the claim email of an unclaimed CC Money row. Written by
# CcMoney#send_claim_email_to, never changed or removed afterwards.
class CcMoneyClaimEmailResend < ApplicationRecord
  belongs_to :cc_money
  # The admin who resent it, shown even after that account is soft-deleted.
  belongs_to :admin, -> { including_deleted }, class_name: "User", inverse_of: false

  # Append-only by convention: a saved resend cannot be updated or destroyed through ActiveRecord, but
  # delete_all and raw SQL bypass this.
  def readonly? = persisted? || super
end
