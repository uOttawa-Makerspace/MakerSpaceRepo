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

  # A user's wallet, locked in `transaction` (see lock_wallet!).
  Wallet = Struct.new(:user, :transaction) do
    # Whether the row lock is still held by THIS connection's open transactions: the locking
    # transaction is open here (so it is the current transaction or one enclosing it), or it
    # was a savepoint that was released (its locks then belong to its parent, checked the same
    # way). A rolled-back savepoint released its locks; a committed top-level transaction too;
    # another connection's transaction never counts.
    def held?
      connection = CcMoney.connection
      tx = transaction
      while tx
        return false unless tx.connection.equal?(connection)

        state = tx.state
        return true unless state.finalized?
        return false unless state.committed?

        tx = released_into(tx)
      end
      false
    end

    private

    # The transaction a released nested transaction handed its locks to: a savepoint's parent,
    # or the parent a lazily-opened requires_new block ran inside (RestartParentTransaction).
    # nil for a top-level transaction (committed: its locks are gone). Rails keeps no public
    # reader for the parent.
    def released_into(tx)
      case tx
      when ActiveRecord::ConnectionAdapters::SavepointTransaction then tx.instance_variable_get(:@parent_transaction)
      when ActiveRecord::ConnectionAdapters::RestartParentTransaction then tx.instance_variable_get(:@parent)
      end
    end
  end

  def self.create_cc_money_from_approval(volunteer_task_id, volunteer_id, cc)
    create(volunteer_task_id: volunteer_task_id, user_id: volunteer_id, cc: cc)
  end

  # Wallet lock, the shared start of every CC spend. Inside the caller's transaction (raises
  # ArgumentError if none is open), it locks the user row FOR NO KEY UPDATE
  # (User::GUARD_LOCK_MODE). House lock order: the user row FIRST, then the rows the caller
  # spends on. Spends of one user are thereby serialised. It changes no session setting: the
  # spends (claim!, checkout!) run in own_transaction, which bounds their lock waits.
  # Returns a Wallet to hand to debit!/debit_all! (which then do not lock again).
  def self.lock_wallet!(user)
    require_caller_transaction!(:lock_wallet!)
    locked = User.where(id: user.id).lock(User::GUARD_LOCK_MODE).take!
    Wallet.new(locked, connection.current_transaction)
  end

  # THE wallet-debit operation (coupon claim, cart checkout). `payer` is a held Wallet from
  # lock_wallet!, or a User, whose wallet is then locked first. Writes one -amount row with
  # `attrs` (e.g. order:, proficient_project:); see debit_all!.
  def self.debit!(payer, amount, **attrs)
    require_caller_transaction!(:debit!)
    wallet = payer.is_a?(Wallet) ? payer : lock_wallet!(payer)
    debit_all!(wallet, [[amount, attrs]]).first
  end

  # Several debit rows (one per cart item) with ONE balance check and ONE cache refresh, on a
  # HELD Wallet (lock_wallet! in this transaction; ArgumentError otherwise): reads the balance
  # uncached under the wallet lock (the
  # request's query cache may hold a SUM from before the lock wait), raises InsufficientBalance
  # if it does not cover the total, else writes the rows and sets the cached users.wallet with
  # update_columns. entries: [[amount, attrs], ...]; amounts are integers >= 0 (0 writes a 0 row,
  # free items).
  def self.debit_all!(wallet, entries)
    unless wallet.is_a?(Wallet) && wallet.held?
      raise ArgumentError, "CcMoney.debit_all! needs a Wallet held by lock_wallet! in this transaction"
    end

    amounts = entries.map { |amount, _| Integer(amount) }
    negative = amounts.find(&:negative?)
    raise InvalidAmount, "debit amount must not be negative (#{negative})" if negative

    user = wallet.user
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
