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

  def self.create_cc_money_from_approval(volunteer_task_id, volunteer_id, cc)
    create(volunteer_task_id: volunteer_task_id, user_id: volunteer_id, cc: cc)
  end

  # Wallet lock: the user row, FOR NO KEY UPDATE (User::GUARD_LOCK_MODE). Every CC spend takes it
  # (debit! does), so spends of one user are serialised and the balance read under it is current.
  # House lock order: the user row FIRST, then the rows the caller spends on (coupon, order), so
  # a caller that must lock both calls this before locking its own rows. Returns the locked user.
  def self.lock_wallet!(user)
    require_caller_transaction!(:lock_wallet!)
    User.where(id: user.id).lock(User::GUARD_LOCK_MODE).take!
  end

  # THE wallet-debit operation: every CC spend goes through here (coupon claim, cart checkout).
  # Runs inside the caller's transaction (raises ArgumentError if none is open), so the caller's
  # own writes (assign the coupon, complete the order) commit or roll back with the debit.
  # Locks the wallet (lock_wallet!), re-reads the balance uncached under that lock (the request's
  # query cache may hold a SUM read before the lock wait), raises InsufficientBalance if it does
  # not cover `amount`, else writes one row of -amount (with `attrs`, e.g. order: /
  # proficient_project:) and refreshes the cached users.wallet. amount 0 writes a 0 row (free items).
  def self.debit!(user, amount, **attrs)
    require_caller_transaction!(:debit!)
    amount = Integer(amount)
    raise ArgumentError, "debit amount must not be negative (#{amount})" if amount.negative?

    locked_user = lock_wallet!(user)
    balance = uncached { where(user_id: locked_user.id).sum(:cc) }
    raise InsufficientBalance.new(balance: balance, amount: amount) if balance < amount

    row = create!(**attrs, user: locked_user, cc: -amount)
    locked_user.update_wallet
    row
  end

  # A caller transaction is a joinable one; the spec suite's fixture transaction is not.
  def self.require_caller_transaction!(name)
    return if connection.transaction_open? && connection.current_transaction.joinable?

    raise ArgumentError, "CcMoney.#{name} must run inside the caller's transaction"
  end
  private_class_method :require_caller_transaction!
end
