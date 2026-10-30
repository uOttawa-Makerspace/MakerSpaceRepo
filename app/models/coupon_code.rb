class CouponCode < ApplicationRecord
  belongs_to :user, optional: true

  scope :unclaimed, -> { where(user_id: nil) }
  scope :claimed, -> { where.not(user_id: nil) }

  # Trades `user`'s CC points for one unclaimed coupon worth `dollar_cost`. Atomic (D-S33): the
  # wallet check, the debit and the assignment happen in ONE transaction, so a claim that loses
  # a race neither charges nor assigns. Returns [:claimed, coupon], [:no_coupon, nil] or
  # [:insufficient_cc, coupon]; only :claimed writes anything. A failed save raises
  # (RecordInvalid / RecordNotSaved) after the transaction has rolled back.
  #
  # Lock order (house rule: the user row first, then other rows):
  #   1. the user row, FOR NO KEY UPDATE (User::GUARD_LOCK_MODE). Serialises every claim by
  #      the same user, so the balance read under it is current and two claims cannot both
  #      spend it (no negative wallet, no paying twice).
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
  # uncached: the request's query cache would otherwise answer the balance SUM with the value
  # the before_action read BEFORE this claim waited on the user lock (a SELECT ... FOR UPDATE
  # does not clear the cache), letting a second claim spend the same points again.
  def self.claim!(user, dollar_cost)
    uncached do
      transaction do
        locked_user = User.where(id: user.id).lock(User::GUARD_LOCK_MODE).take!
        coupon = unclaimed.where(dollar_cost: dollar_cost).order(:id).lock(User::GUARD_LOCK_MODE).first
        if coupon.nil? || !coupon.user_id.nil? # guard, re-checked on the locked row version
          [:no_coupon, nil]
        elsif locked_user.get_total_cc < coupon.cc_cost.to_i
          [:insufficient_cc, coupon]
        else
          payment = CcMoney.make_new_payment(locked_user, coupon.cc_cost.to_i)
          raise ActiveRecord::RecordNotSaved, "coupon payment not saved" unless payment.persisted?

          coupon.update!(user: locked_user)
          [:claimed, coupon]
        end
      end
    end
  end

  def title
    "$#{dollar_cost} off MakerStore"
  end
end
