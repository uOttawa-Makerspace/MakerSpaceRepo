class Membership < ApplicationRecord
  include ShopifyConcern

  belongs_to :user
  belongs_to :membership_tier

  attribute :status, :string, default: 'paid'

  enum :status, {
         pending: 'pending',
         paid: 'paid',
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

  def checkout_link
    # Faculty memberships never trigger Shopify calls
    return '/' if faculty?
    shopify_draft_order['invoiceUrl']
  end

  # Pending -> paid in one conditional UPDATE, so it holds against a concurrent revoke or a second payment.
  # False when the membership was not pending (nothing changed).
  def mark_paid_if_pending
    self.class.where(id: id, status: 'pending').update_all(status: 'paid', updated_at: Time.current) == 1
  end

  def membership_title
    membership_tier.title(I18n.locale)
  end

  def active?
    end_date > Time.current && status == 'paid'
  end

  def faculty?
    membership_tier.title_en.downcase.include?('faculty')
  end

  # A custom grant repeated within this window is a double submit, not a second grant.
  DUPLICATE_GRANT_WINDOW = 1.minute

  # An admin's paid custom membership of `days`, stacked after the user's latest active one. Under the user's row
  # lock, so two submits cannot both pass the check. Nil (nothing added) when the same grant was just made.
  def self.grant_custom(user, days)
    tier = MembershipTier.find_by!(title_en: 'Custom Membership')
    user.with_lock do
      next if recent_custom_grant?(user, tier, days)

      start_time = calculate_end_date(user)
      create!(user: user, membership_tier: tier, status: 'paid', start_date: start_time, end_date: start_time + days.days)
    end
  end

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

  def set_dates
    self.start_date ||= Membership.calculate_end_date(user)
    self.end_date ||= Membership.calculate_end_date(user) + duration.days
  end
end
