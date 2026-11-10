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

  # The Shopify invoice URL that pays this membership, creating the draft order if there is none yet. Nil when the
  # stored draft no longer exists on Shopify (see .begin_purchase). Shopify not answering raises.
  def checkout_link
    # Faculty memberships never trigger Shopify calls
    return '/' if faculty?

    create_and_store_remote_draft_order if shopify_draft_order_id.blank?
    raise 'Membership has no draft order after creating one' if shopify_draft_order_id.blank?

    state, draft = fetch_shopify_draft_order_result
    raise 'Shopify did not answer the draft order check' if state == :error

    draft && draft['invoiceUrl']
  end

  # Where a purchase of `tier_id` starts: the user's pending membership for the tier and the link that pays it.
  # A draft that Shopify no longer has cannot be paid, so that membership is marked failed (kept) and a fresh
  # pending one is used.
  def self.begin_purchase(user, tier_id)
    membership = claim_pending(user, tier_id)
    link = membership.checkout_link
    return [membership, link] if link

    membership.update!(status: 'failed')
    membership = claim_pending(user, tier_id)
    [membership, membership.checkout_link]
  end

  # The user's pending membership for the tier, or a new one. Under the user's row lock, so repeated or
  # simultaneous purchases share one row. A reused row gets dates from today, as a new one would.
  def self.claim_pending(user, tier_id)
    user.with_lock do
      membership = user.memberships.pending.where(membership_tier_id: tier_id).order(:id).first
      if membership
        membership.renew_dates
        membership
      else
        user.memberships.create!(membership_tier_id: tier_id)
      end
    end
  end

  def renew_dates
    start_time = Membership.calculate_end_date(user)
    update!(start_date: start_time, end_date: start_time + duration.days)
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

  def create_and_store_remote_draft_order
    new_id, line_items = create_remote_draft_order
    store_shopify_draft_order_id(new_id, line_items)
  end

  # The draft was just created on Shopify (no row lock held). The id is stored only if no other request stored
  # one first; the draft that lost the race (or could not be stored) is deleted, so one membership has one
  # payable draft.
  def store_shopify_draft_order_id(new_id, _line_items)
    kept = false
    begin
      transaction do
        lock!
        if shopify_draft_order_id.blank? && pending?
          update_column(:shopify_draft_order_id, new_id)
          kept = true
        end
      end
    rescue StandardError
      discard_unused_draft(new_id)
      raise
    end
    discard_unused_draft(new_id) unless kept
  end

  def discard_unused_draft(gid)
    result = ShopifyConcern::DraftRemoval.call(gid)
    return unless result.outcome == :open

    raise "Shopify did not delete the unused draft order #{gid}"
  rescue StandardError => e
    Rails.error.report(e, handled: true, severity: :error, context: { membership_id: id, step: 'delete_unused_shopify_draft_order' })
  end

  def set_dates
    self.start_date ||= Membership.calculate_end_date(user)
    self.end_date ||= Membership.calculate_end_date(user) + duration.days
  end
end
