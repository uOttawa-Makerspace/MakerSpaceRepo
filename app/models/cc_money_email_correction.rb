# frozen_string_literal: true

# The record of one admin correcting the purchase email of an unclaimed CC Money row. Written by
# CcMoney#correct_purchase_email!, never changed or removed afterwards.
class CcMoneyEmailCorrection < ApplicationRecord
  belongs_to :cc_money
  belongs_to :admin, class_name: "User"

  # A saved correction can be neither updated nor destroyed.
  def readonly? = persisted? || super
end
