# frozen_string_literal: true

class CcMoney < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :volunteer_task, optional: true
  belongs_to :proficient_project, optional: true
  belongs_to :order, optional: true
  has_many :email_corrections, class_name: "CcMoneyEmailCorrection", dependent: :restrict_with_error
  has_one :latest_email_correction, -> { order(id: :desc) },
          class_name: "CcMoneyEmailCorrection", inverse_of: :cc_money, dependent: :restrict_with_error

  has_many :claim_email_resends, class_name: "CcMoneyClaimEmailResend", dependent: :restrict_with_error
  has_one :latest_claim_email_resend, -> { order(id: :desc) },
          class_name: "CcMoneyClaimEmailResend", inverse_of: :cc_money, dependent: :restrict_with_error

  # How long a mailed claim link works. A resend (send_claim_email_to) starts a new window.
  CLAIM_TOKEN_LIFETIME = 30.days
  CLAIM_TOKEN_PURPOSE = :cc_claim

  scope :unclaimed, -> { where(linked: false) }

  # The address the purchase was made with; the claim is only for the account with this email.
  normalizes :purchaser_email, with: ->(email) { email.strip.downcase }

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

  # The unique index that lets a volunteer task pay one user once (rows flagged legacy_duplicate are the old
  # double awards it ignores).
  TASK_AWARD_INDEX = "index_cc_moneys_on_user_and_task_award"

  # Pays a task's CC money to a volunteer. Returns the new row, or nil when the user already holds an award for
  # the task (the database refuses a second one), in which case nothing is written.
  def self.create_cc_money_from_approval(volunteer_task_id, volunteer_id, cc)
    transaction(requires_new: true) do
      create(volunteer_task_id: volunteer_task_id, user_id: volunteer_id, cc: cc)
    end
  rescue ActiveRecord::RecordNotUnique => e
    raise unless e.message.include?(TASK_AWARD_INDEX)

    nil
  end

  # A purchase made without an account that nobody has claimed yet.
  def unclaimed? = !linked?

  # The row a mailed claim link names, or nil unless the token is ours, unexpired and of the row's current
  # generation (a resend revokes the links sent before). Raises ActiveRecord::RecordNotFound when the token
  # is valid but its row no longer exists.
  def self.for_claim_token(token)
    id, generation = verified_claim_token(token)
    return if id.nil?

    row = find_by_id(id) || raise(ActiveRecord::RecordNotFound, "CcMoney #{id}")
    row if row.current_claim_generation?(generation)
  end

  # [id, generation] signed in a token, nil when the token is not a string, is not ours, was tampered with or
  # has expired.
  def self.verified_claim_token(token)
    return unless token.is_a?(String)

    claim_verifier.verified(token, purpose: CLAIM_TOKEN_PURPOSE) || legacy_claim_token(token)
  end
  private_class_method :verified_claim_token

  # Temporary: reads a token issued before claim links carried a generation (the bare row id) as generation 0,
  # so it works only until the row is resent. Remove this 30 days after the release that added generations.
  def self.legacy_claim_token(token)
    id = claim_verifier.verified(token)
    [id, 0] if id.is_a?(Integer)
  end
  private_class_method :legacy_claim_token

  def self.claim_verifier = Rails.application.message_verifier(:cc)

  # The signed token in the claim link mailed to the buyer (see CcMoneysController#link_cc_to_user). It
  # expires after CLAIM_TOKEN_LIFETIME and stops working when the row's generation moves on.
  def claim_token
    self.class.claim_verifier.generate([id, claim_token_generation], purpose: CLAIM_TOKEN_PURPOSE, expires_in: CLAIM_TOKEN_LIFETIME)
  end

  def current_claim_generation?(generation) = claim_token_generation == generation

  # Only the account bought with this email may claim it; rows bought before the email was recorded have none.
  def claimable_by?(user)
    unclaimed? && purchaser_email.present? && purchaser_email == user.email.to_s.strip.downcase
  end

  # Revokes the claim links sent so far (raises the generation) so the caller can mail a new one
  # (`claim_token`), all under the row lock so two resends, or a resend and a claim, cannot interleave.
  # Records `email` as the purchase address when the row has none; an address already recorded is never
  # replaced. Returns :sent, or the reason nothing was changed: :already_linked, :email_invalid or
  # :email_mismatch (not the recorded purchase address). A :sent resend is recorded (CcMoneyClaimEmailResend)
  # with the admin `by` and the address.
  def send_claim_email_to(email, by:)
    address = email.to_s.strip
    with_lock do
      next :already_linked if linked?
      next :email_invalid unless address.match?(URI::MailTo::EMAIL_REGEXP)
      next :email_mismatch unless addressed_to?(address)

      update!(purchaser_email: purchaser_email.presence || address, claim_token_generation: claim_token_generation + 1)
      claim_email_resends.create!(admin: by, email: address)
      :sent
    end
  end

  # An admin fixes the purchase email of an unclaimed row (a mistyped address at checkout). Under the row lock it
  # writes the normalised address, raises the generation so every link sent before stops working, and records who
  # changed what in a CcMoneyEmailCorrection. The caller then mails a new link (`claim_token`) to the new address.
  # Returns :corrected, or the reason nothing was changed: :already_linked, :email_invalid or :email_unchanged.
  def correct_purchase_email(new_email, by:)
    address = self.class.normalize_value_for(:purchaser_email, new_email.to_s)
    with_lock do
      next :already_linked if linked?
      next :email_invalid unless valid_purchase_email?(address)
      next :email_unchanged if address == purchaser_email

      email_corrections.create!(admin: by, old_email: purchaser_email, new_email: address)
      update!(purchaser_email: address, claim_token_generation: claim_token_generation + 1)
      :corrected
    end
  end

  # Gives an unclaimed purchase to `user`. The row is re-read under its lock, so of two claims racing for
  # the same row only the first writes. Returns :linked, :already_linked (the row keeps its owner),
  # :superseded (a resend raised the generation since this copy was loaded, so the link the caller holds is
  # revoked) or :not_saved (the update was refused; see `errors`).
  def link_to(user)
    generation = claim_token_generation
    with_lock do
      next :already_linked if linked?
      next :superseded unless current_claim_generation?(generation)

      update(user: user, linked: true) ? :linked : :not_saved
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
    require_caller_transaction!(:debit_all!)
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

  private

  def valid_purchase_email?(address)
    address.match?(URI::MailTo::EMAIL_REGEXP) && User.email_shape_error(address).nil?
  end

  # May a claim mail for this row go to `address`: any address when none is recorded, else the recorded one.
  def addressed_to?(address)
    purchaser_email.blank? || purchaser_email == self.class.normalize_value_for(:purchaser_email, address)
  end
end
