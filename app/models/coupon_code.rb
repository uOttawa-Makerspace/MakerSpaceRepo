class CouponCode < ApplicationRecord
  belongs_to :user, optional: true

  scope :unclaimed, -> { where(user_id: nil) }
  scope :claimed, -> { where.not(user_id: nil) }

  # Trades `user`'s CC points for one unclaimed coupon worth `dollar_cost` AT `cc_cost`, the
  # price the user confirmed (a same-dollar coupon at another price is never picked; a blank
  # cc_cost matches nothing). Atomic (D-S33): the
  # wallet check, the debit and the assignment happen in ONE transaction, so a claim that loses
  # a race neither charges nor assigns. Returns [:claimed, coupon], [:no_coupon, nil] or
  # [:insufficient_cc, coupon]; only :claimed writes anything. A failed save raises
  # (RecordInvalid / RecordNotSaved) after the transaction has rolled back.
  #
  # Lock order (house rule: the user row first, then other rows):
  #   1. the wallet: the user row (CcMoney.lock_wallet!, FOR NO KEY UPDATE). Serialises this
  #      claim with every other CC spend of the user (claims, cart checkouts), so the balance
  #      CcMoney.debit! reads under it is current: no negative wallet, no paying twice.
  #   2. the lowest-id unclaimed coupon row, plain FOR NO KEY UPDATE: a second claimant WAITS
  #      for the holder to commit or roll back (no SKIP LOCKED, which would answer "already
  #      claimed" while the holder could still roll back and free it). When the wait ends on a
  #      coupon the holder claimed, Postgres re-checks `user_id IS NULL` on the new row version,
  #      drops that row and moves on to the next unclaimed one (LockRows sits under the LIMIT;
  #      the two-coupon race spec covers it). The locked row is still re-checked as a guard
  #      (claimed -> :no_coupon).
  # Only the claimant's own user row is locked before a coupon, so two claimants never hold
  # locks the other needs in the opposite order: no deadlock.
  #
  # The debit is CcMoney.debit! (balance re-read uncached under the wallet lock).
  #
  # Always its own top-level transaction (own_transaction; the only caller is
  # DiscountCodesController#create): lock_wallet! bounds its lock waits with SET LOCAL
  # lock_timeout (LockWaitTimeout -> rollback -> "not created properly"), which COMMIT/ROLLBACK
  # then ends; inside a caller's transaction it raises ArgumentError instead.
  def self.claim!(user, dollar_cost, cc_cost)
    coupon = nil
    uncached do
      own_transaction("claim!") do
        wallet = CcMoney.lock_wallet!(user) # the user row first (house lock order)
        coupon = cc_cost.blank? ? nil : unclaimed.where(dollar_cost: dollar_cost, cc_cost: cc_cost)
                                                  .order(:id).lock(User::GUARD_LOCK_MODE).first
        next [:no_coupon, nil] if coupon.nil? || !coupon.user_id.nil? # guard, re-checked on the locked row

        CcMoney.debit!(wallet, coupon.cc_cost.to_i)
        coupon.update!(user: wallet.user)
        [:claimed, coupon]
      end
    end
  rescue CcMoney::InsufficientBalance
    [:insufficient_cc, coupon] # the transaction has rolled back: nothing written
  end

  def title
    "$#{dollar_cost} off MakerStore"
  end
end
