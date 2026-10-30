# frozen_string_literal: true

class CcMoney < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :volunteer_task, optional: true
  belongs_to :proficient_project, optional: true
  belongs_to :order, optional: true

  # The balance does not cover the debit. Raised inside the caller's transaction, so it rolls
  # back everything the caller wrote there.
  class InsufficientBalance < StandardError
    attr_reader :balance, :amount

    def initialize(balance:, amount:)
      @balance = balance
      @amount = amount
      super("CC balance #{balance} does not cover #{amount}")
    end
  end

  # A negative debit amount (e.g. a legacy negative price snapshot). Nothing is written.
  class InvalidAmount < ArgumentError; end

  def self.create_cc_money_from_approval(volunteer_task_id, volunteer_id, cc)
    create(volunteer_task_id: volunteer_task_id, user_id: volunteer_id, cc: cc)
  end

  # Wallet lock, the shared start of every CC spend. Inside the caller's transaction (raises
  # ArgumentError if none is open), it locks the user row FOR NO KEY UPDATE
  # (User::GUARD_LOCK_MODE) and returns the locked user. House lock order: the user row FIRST,
  # then the rows the caller spends on (coupon, order), so a caller that locks both calls this
  # first. Spends of one user are thereby serialised. It changes no session setting: the spends
  # (claim!, checkout!) run in own_transaction, which bounds their lock waits.
  def self.lock_wallet!(user)
    require_caller_transaction!(:lock_wallet!)
    User.where(id: user.id).lock(User::GUARD_LOCK_MODE).take!
  end

  # THE wallet-debit operation (coupon claim, cart checkout): one -amount row with `attrs`
  # (e.g. order:, proficient_project:); see debit_all!.
  def self.debit!(user, amount, **attrs)
    require_caller_transaction!(:debit!)
    debit_all!(user, [[amount, attrs]]).first
  end

  # Several debit rows (one per cart item) with ONE balance check and ONE cache refresh, inside
  # the caller's transaction (ArgumentError otherwise). It always takes the wallet lock itself
  # (lock_wallet!): re-locking a row this transaction already holds is one cheap statement and
  # always correct. Under the lock it reads the balance uncached (the request's query cache may
  # hold a SUM from before the lock wait), raises InsufficientBalance if it does not cover the
  # total, else writes the rows and sets the cached users.wallet with update_columns.
  # entries: [[amount, attrs], ...]; amounts are integers >= 0 (0 writes a 0 row, free items).
  def self.debit_all!(user, entries)
    require_caller_transaction!(:debit!)
    amounts = entries.map { |amount, _| Integer(amount) }
    negative = amounts.find(&:negative?)
    raise InvalidAmount, "debit amount must not be negative (#{negative})" if negative

    user = lock_wallet!(user)
    balance = uncached { where(user_id: user.id).sum(:cc) }
    total = amounts.sum
    raise InsufficientBalance.new(balance: balance, amount: total) if balance < total

    rows = entries.zip(amounts).map { |(_, attrs), amount| create!(**(attrs || {}), user: user, cc: -amount) }
    user.update_columns(wallet: balance - total)
    rows
  end

  def self.require_caller_transaction!(name)
    return if caller_transaction_open?

    raise ArgumentError, "CcMoney.#{name} must run inside the caller's transaction"
  end
  private_class_method :require_caller_transaction!
end
