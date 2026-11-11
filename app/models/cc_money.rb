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

  # Task awards held more than once by one user for one task: [[user_id, volunteer_task_id, [row ids]], ...].
  # Read only; the rows are never changed.
  def self.duplicate_task_awards
    where.not(volunteer_task_id: nil)
         .where.not(user_id: nil)
         .group(:user_id, :volunteer_task_id)
         .having("COUNT(*) > 1")
         .pluck(:user_id, :volunteer_task_id, Arel.sql("ARRAY_AGG(id ORDER BY id)"))
  end

  def self.create_cc_money_from_approval(volunteer_task_id, volunteer_id, cc)
    create(volunteer_task_id: volunteer_task_id, user_id: volunteer_id, cc: cc)
  end

  scope :unlinked, -> { where(linked: false) }

  # A purchase made without an account that nobody has claimed yet.
  def claimable? = !linked?

  # How long a mailed claim link works. A resend (reissue_claim_token!) starts a new window.
  CLAIM_TOKEN_LIFETIME = 30.days
  CLAIM_TOKEN_PURPOSE = :cc_claim

  # The address the purchase was made with; the claim is only for the account with this email.
  normalizes :purchaser_email, with: ->(email) { email.strip.downcase }

  def self.claim_verifier = Rails.application.message_verifier(:cc)

  # [id, generation] signed in a token read by verified_claim_token, nil when the token is not ours,
  # tampered with or expired. A token issued before claim links carried a generation is the bare id; it
  # reads as generation 0, so it works only until the row is resent.
  def self.verified_claim_token(token)
    signed = claim_verifier.verified(token, purpose: CLAIM_TOKEN_PURPOSE)
    return signed if signed

    legacy_id = claim_verifier.verified(token)
    [legacy_id, 0] if legacy_id.is_a?(Integer)
  end

  # The signed token in the claim link mailed to the buyer (see CcMoneysController#link_cc_to_user). It
  # expires after CLAIM_TOKEN_LIFETIME and stops working when the row's generation moves on.
  def claim_token
    self.class.claim_verifier.generate([id, claim_token_generation], purpose: CLAIM_TOKEN_PURPOSE, expires_in: CLAIM_TOKEN_LIFETIME)
  end

  # Is a token's generation the row's current one (older links are revoked by a resend).
  def claim_generation?(generation) = claim_token_generation == generation

  # Only the account bought with this email may claim it; rows bought before the email was recorded have none.
  def purchased_by?(user)
    purchaser_email.present? && purchaser_email == user.email.to_s.strip.downcase
  end

  # May a claim mail for this row go to `email`: any address when none is recorded, else the recorded one.
  def addressed_to?(email)
    purchaser_email.blank? || purchaser_email == self.class.normalize_value_for(:purchaser_email, email)
  end

  # Revokes the links sent so far and returns a new token, under the row lock so two resends or a resend
  # and a claim cannot interleave. Records `email` as the purchase address when the row has none (an
  # address already recorded is never replaced). Nil when the row was claimed meanwhile.
  def reissue_claim_token!(email)
    with_lock do
      next if linked?

      update!(purchaser_email: purchaser_email.presence || email, claim_token_generation: claim_token_generation + 1)
      claim_token
    end
  end

  # Gives an unlinked purchase to `user`. The row is re-read under its lock, so of two claims racing
  # for the same row only the first writes; the other (or a repeat of the first) returns false and the
  # row keeps its owner. Also false when the row cannot be saved; `linked?` tells the two apart.
  def link_to(user)
    with_lock do
      next false if linked?

      update(user: user, linked: true)
    end
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
