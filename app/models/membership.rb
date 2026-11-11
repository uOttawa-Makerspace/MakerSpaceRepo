class Membership < ApplicationRecord
  include ShopifyConcern
  include Checkout
  include Expiry

  belongs_to :user
  belongs_to :membership_tier

  attribute :status, :string, default: 'paid'

  enum :status, {
         pending: 'pending',
         paid: 'paid',
         # A checkout never paid, closed by Membership::Expiry (legacy rows may be failed too).
         failed: 'failed',
         revoked: 'revoked'
       },
       default: 'pending'

  before_create :set_dates

  scope :active, -> { where('end_date > ?', Time.current).where(status: :paid).order(end_date: :desc) }

  delegate :duration, to: :membership_tier

  def self.shopify_draft_order_key_name
    'membership'
  end

  def shopify_draft_order_line_items
    [{ originalUnitPrice: membership_tier.price(user).to_s, quantity: 1, title: membership_title }]
  end

  # Pending -> paid in one conditional UPDATE, so it holds against a concurrent revoke or a second payment. The
  # membership starts when the latest active one ends (or now) and lasts the tier's duration, worked out at the
  # moment of payment under the member's row lock, so payments made together stack instead of overlapping.
  # False when the membership was not pending (nothing changed).
  def mark_paid_if_pending
    user.with_lock do
      start_time = Membership.calculate_end_date(user)
      change_if_pending({}, status: 'paid', start_date: start_time, end_date: start_time + duration.days)
    end
  end

  def membership_title
    membership_tier.title(I18n.locale)
  end

  def active?
    paid? && end_date > Time.current
  end

  # Only a paid membership can be taken away; an unpaid checkout (pending or failed) is not one yet.
  def revocable?
    paid?
  end

  # The membership was not paid, so there is nothing to revoke.
  class NotRevocable < StandardError; end

  # Paid -> revoked. Raises NotRevocable, changing nothing, for a membership that is not paid.
  def revoke!
    raise NotRevocable, "This membership is #{status}, not paid, so it cannot be revoked." unless revocable?

    update!(status: 'revoked')
  end

  def faculty?
    membership_tier.title_en.downcase.include?('faculty')
  end

  # A custom grant repeated within this window is a double submit, not a second grant.
  DUPLICATE_GRANT_WINDOW = 1.minute

  # The same custom grant was made for the member within DUPLICATE_GRANT_WINDOW; nothing was added.
  class DuplicateGrant < StandardError; end

  # An admin's paid custom membership of `days`, stacked after the user's latest active one. Under the user's row
  # lock, so two submits cannot both pass the check. Raises DuplicateGrant when the same grant was just made.
  def self.grant_custom!(user, days)
    tier = MembershipTier.find_by!(title_en: 'Custom Membership')
    user.with_lock do
      raise DuplicateGrant if recent_custom_grant?(user, tier, days)

      create_stacked!(user, tier, days)
    end
  end

  # A paid membership of the tier's duration, stacked after the user's latest active one, made under the user's row
  # lock. Used for a payment that arrives without a pending membership to pay.
  def self.grant!(user, tier)
    user.with_lock { create_stacked!(user, tier, tier.duration) }
  end

  # The caller holds the user's row lock.
  def self.create_stacked!(user, tier, days)
    start_time = calculate_end_date(user)
    create!(user: user, membership_tier: tier, status: 'paid', start_date: start_time, end_date: start_time + days.days)
  end
  private_class_method :create_stacked!

  def self.recent_custom_grant?(user, tier, days)
    user.memberships.paid.where(membership_tier: tier).where('created_at > ?', DUPLICATE_GRANT_WINDOW.ago)
        .any? { |m| m.end_date - m.start_date == days.days }
  end
  private_class_method :recent_custom_grant?

  def self.calculate_end_date(user)
    last_active =
      user
        .memberships
        .active
        .first
    last_active ? last_active.end_date : Time.current
  end

  private

  # The one way a pending membership changes: a conditional UPDATE that applies `changes` only while the row is still
  # pending and matches `expected` (columns the caller saw), so it cannot overwrite what another request did. True
  # when this call changed the row.
  def change_if_pending(expected, **changes)
    self.class.where(id: id, status: 'pending').where(expected).update_all(changes.merge(updated_at: Time.current)) == 1
  end

  # A paid membership made without dates (the faculty grant) gets them now; a pending one has none until paid.
  def set_dates
    return unless paid?

    self.start_date ||= Membership.calculate_end_date(user)
    self.end_date ||= Membership.calculate_end_date(user) + duration.days
  end
end
