# frozen_string_literal: true

# A member's purchase of a tier: the pending membership is the checkout record, and its Shopify draft order is what
# the member pays. At most one pending membership exists per member and tier, and a pending membership has at most
# one payable draft at any moment.
#
# Concurrency: the user's row lock serializes claiming a pending membership (Shopify itself is called outside any
# lock). Every change to a membership's draft id or status is a conditional UPDATE from the state the caller saw
# (Membership#change_if_pending), so a request holding an out-of-date view of the row changes nothing: it adopts a
# draft only while the row has none, releases only the draft it deleted, and fails the checkout only when the draft
# it holds is the one Shopify no longer has. A draft that loses such a race is deleted.
module Membership::Checkout
  extend ActiveSupport::Concern

  # Passes over a checkout whose row changed under the request (see .begin_purchase) before giving up.
  CHECKOUT_ATTEMPTS = 3

  class_methods do
    # The Shopify invoice URL that pays the user's pending membership for the tier (made now if there is none). A
    # draft that Shopify no longer has cannot be paid, so its membership is marked failed (kept) and a fresh pending
    # one is used; a row that changed under this request is looked up again. Shopify not answering raises.
    def begin_purchase(user, tier_id)
      CHECKOUT_ATTEMPTS.times do
        link = claim_pending(user, tier_id).checkout_link
        return link if link
      end
      raise "Checkout for tier #{tier_id} did not settle after #{CHECKOUT_ATTEMPTS} attempts"
    end

    # The user's pending membership for the tier, or a new one. Under the user's row lock, so repeated or
    # simultaneous purchases share one row. A pending membership has no dates: they are set when it is paid.
    def claim_pending(user, tier_id)
      user.with_lock do
        user.memberships.pending.where(membership_tier_id: tier_id).order(:id).first ||
          user.memberships.create!(membership_tier_id: tier_id)
      end
    end
  end

  # The invoice URL that pays this membership, creating its draft order if there is none yet. Nil when this
  # membership is no longer a checkout that can be paid (its draft was gone, or another request changed the row).
  def checkout_link
    # Faculty memberships never trigger Shopify calls
    return '/' if faculty?

    @checkout_link ||= fetch_checkout_link
  end

  private

  def fetch_checkout_link
    draft = fetch_or_create_draft
    draft = reprice_draft if draft && reprice?(draft)
    return fail_checkout_for_gone_draft unless draft

    draft['invoiceUrl']
  end

  # The membership's Shopify draft order, made first if it has none; nil when Shopify no longer has it.
  def fetch_or_create_draft
    create_and_store_remote_draft_order if shopify_draft_order_id.blank?
    raise 'Membership has no draft order after creating one' if shopify_draft_order_id.blank?

    state, draft = fetch_shopify_draft_order_result
    raise 'Shopify did not answer the draft order check' if state == :error

    draft
  end

  # Only the draft this membership holds, and only if it is still the one Shopify lacks, fails the checkout.
  def fail_checkout_for_gone_draft
    change_if_pending({ shopify_draft_order_id: shopify_draft_order_id }, status: 'failed')
    nil
  end

  # A payable draft whose line was priced differently from what the tier charges this member now. A draft that
  # does not say its price is taken as current. A completed draft (paid, order not applied yet) is never replaced:
  # a second payable draft would let the member pay twice.
  def reprice?(draft)
    amount = draft.dig('lineItems', 'nodes')&.first&.dig('originalUnitPriceSet', 'shopMoney', 'amount')
    ShopifyConcern::DraftRemoval.payable?(draft) && amount.present? && BigDecimal(amount) != membership_tier.price(user)
  end

  # Replaces the out-of-date draft with one at today's price, keeping one payable draft at all times: the old draft
  # is deleted first, and only when Shopify confirms it is gone is its id released and a new draft made. If it
  # cannot be deleted (reported), the member keeps the old draft and pays the price the open invoice shows.
  def reprice_draft
    stale_id = shopify_draft_order_id
    return fetch_or_create_draft unless delete_draft(stale_id, 'stale')

    change_if_pending({ shopify_draft_order_id: stale_id }, shopify_draft_order_id: nil)
    reload
    fetch_or_create_draft
  end

  def create_and_store_remote_draft_order
    new_id, = create_remote_draft_order
    keep_or_discard_draft(new_id)
  end

  # ShopifyConcern's hook for a draft it has just created.
  def store_shopify_draft_order_id(new_id, _line_items)
    keep_or_discard_draft(new_id)
  end

  # The draft was just created on Shopify (no lock held); keep it only if no other request stored one first. A
  # draft that lost the race, or could not be stored, is deleted, so one membership has one payable draft.
  def keep_or_discard_draft(new_id)
    discard_unused_draft(new_id) unless adopt_draft(new_id)
  rescue StandardError
    discard_unused_draft(new_id)
    raise
  end

  # Stores the draft id when the membership is still pending and has none; either way the row is read again, so
  # it holds whichever draft won. True when this draft was stored.
  def adopt_draft(new_id)
    stored = change_if_pending({ shopify_draft_order_id: nil }, shopify_draft_order_id: new_id)
    reload
    stored
  end

  def discard_unused_draft(gid)
    delete_draft(gid, 'unused')
  end

  # Deletes the draft on Shopify. True when it is deleted or gone. False when it was paid meanwhile, and false
  # (reported) when it is still open or Shopify could not be asked: the draft is then still payable.
  def delete_draft(gid, what)
    outcome = ShopifyConcern::DraftRemoval.call(gid).outcome
    raise "Shopify did not delete the #{what} draft order #{gid}" if outcome == :open

    outcome != :completed
  rescue StandardError => e
    Rails.error.report(e, handled: true, severity: :error, context: { membership_id: id, step: "delete_#{what}_shopify_draft_order" })
    false
  end
end
