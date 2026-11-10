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

  # Concurrency: the user's row lock serializes claiming a pending membership and granting a custom one; the
  # membership's own row lock guards storing the Shopify draft id (Shopify itself is called outside any lock); the
  # status changes to paid and failed are conditional UPDATEs from pending, so they cannot overwrite another state.

  # The Shopify invoice URL that pays this membership, creating the draft order if there is none yet. Nil when the
  # stored draft no longer exists on Shopify (see .begin_purchase). Shopify not answering raises.
  def checkout_link
    # Faculty memberships never trigger Shopify calls
    return '/' if faculty?

    @checkout_link ||= fetch_checkout_link
  end

  # The user's pending membership for the tier (made now if there is none) with a draft order that can be paid;
  # its checkout_link is the way to pay. A draft that Shopify no longer has cannot be paid, so that membership is
  # marked failed (kept, and only if still pending) and a fresh pending one is used.
  def self.begin_purchase(user, tier_id)
    membership = claim_pending(user, tier_id)
    return membership if membership.checkout_link

    membership.mark_failed_if_pending
    claim_pending(user, tier_id).tap(&:checkout_link)
  end

  # The user's pending membership for the tier, or a new one. Under the user's row lock, so repeated or
  # simultaneous purchases share one row. A reused row gets dates from today, as a new one would.
  def self.claim_pending(user, tier_id)
    user.with_lock do
      membership = user.memberships.pending.where(membership_tier_id: tier_id).order(:id).first
      membership ? membership.reuse_for_purchase : user.memberships.create!(membership_tier_id: tier_id)
    end
  end

  def reuse_for_purchase
    renew_dates
    self
  end

  # Pending -> paid in one conditional UPDATE, so it holds against a concurrent revoke or a second payment.
  # False when the membership was not pending (nothing changed).
  def mark_paid_if_pending
    update_status_if_pending('paid')
  end

  # Pending -> failed, the same way; a paid, revoked or failed membership is never touched.
  def mark_failed_if_pending
    update_status_if_pending('failed')
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

  # The same custom grant was made for the member within DUPLICATE_GRANT_WINDOW; nothing was added.
  class DuplicateGrant < StandardError; end

  # An admin's paid custom membership of `days`, stacked after the user's latest active one. Under the user's row
  # lock, so two submits cannot both pass the check. Raises DuplicateGrant when the same grant was just made.
  def self.grant_custom!(user, days)
    tier = MembershipTier.find_by!(title_en: 'Custom Membership')
    user.with_lock do
      raise DuplicateGrant if recent_custom_grant?(user, tier, days)

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

  def renew_dates
    start_time = Membership.calculate_end_date(user)
    update!(start_date: start_time, end_date: start_time + duration.days)
  end

  def update_status_if_pending(status)
    self.class.where(id: id, status: 'pending').update_all(status: status, updated_at: Time.current) == 1
  end

  def fetch_checkout_link
    create_and_store_remote_draft_order if shopify_draft_order_id.blank?
    raise 'Membership has no draft order after creating one' if shopify_draft_order_id.blank?

    state, draft = fetch_shopify_draft_order_result
    raise 'Shopify did not answer the draft order check' if state == :error

    draft && draft['invoiceUrl']
  end

  def create_and_store_remote_draft_order
    new_id, line_items = create_remote_draft_order
    store_shopify_draft_order_id(new_id, line_items)
  end

  # The draft was just created on Shopify (no lock held); keep it only if no other request stored one first. A
  # draft that lost the race, or could not be stored, is deleted, so one membership has one payable draft.
  def store_shopify_draft_order_id(new_id, _line_items)
    stored = begin
      store_draft_id_unless_taken(new_id)
    rescue StandardError
      discard_unused_draft(new_id)
      raise
    end
    discard_unused_draft(new_id) unless stored
  end

  # Stores the draft id under the row lock when the membership is still pending and has none. True when stored.
  def store_draft_id_unless_taken(new_id)
    transaction do
      lock!
      next false unless shopify_draft_order_id.blank? && pending?

      update_column(:shopify_draft_order_id, new_id)
      true
    end
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
