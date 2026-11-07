class KeyTransaction < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :key, optional: true

  validates :user, presence: true
  validates :key, presence: true
  validates :deposit_amount, presence: true

  # A key has at most one open transaction. Key#assign_to! holds the key's row lock while it checks, and the
  # partial unique index on open transactions is the final guarantee.
  validates :key_id,
            uniqueness: { conditions: -> { not_returned }, message: "already has an open transaction" },
            if: -> { return_date.nil? }

  scope :returned, -> { where.not(return_date: nil) }
  scope :not_returned, -> { where(return_date: nil) }
  scope :awaiting_deposit_return,
        -> { where.not(return_date: nil).and(where(deposit_return_date: nil)) }

  # Closes the transaction today. A zero deposit is marked returned the same
  # day unless a deposit return date is given.
  def close!(deposit_return_date = nil)
    update!(
      return_date: Date.today,
      deposit_return_date: deposit_return_date || (Time.zone.today if deposit_amount.zero?)
    )
  end
end
