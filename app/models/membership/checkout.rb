# frozen_string_literal: true

class Membership
  # A member's purchase of a tier: the pending membership is the checkout record, and its Shopify draft order is what
  # the member pays. At most one pending membership exists per member and tier, and a pending membership has at most
  # one payable draft at any moment.
  #
  # Concurrency: the user's row lock serializes claiming a pending membership (Shopify itself is called outside any
  # lock). Every change to a membership's draft id or status is a conditional UPDATE from the state the caller saw
  # (Membership#change_if_pending), so a request holding an out-of-date view of the row changes nothing: it adopts a
  # draft only while the row has none and releases only the draft it deleted. A draft that loses such a race is
  # deleted, and the loser serves the winner's draft.
  module Checkout
    extend ActiveSupport::Concern

    class_methods do
      # Member and tier pairs that have more than one pending membership, as [user_id, tier_id, [membership ids]],
      # oldest first. Reads only.
      def pending_duplicates
        pending.group_by { |m| [m.user_id, m.membership_tier_id] }
               .select { |_pair, rows| rows.size > 1 }
               .map { |(user_id, tier_id), rows| [user_id, tier_id, rows.map(&:id).sort] }
               .sort
      end

      # The Shopify invoice URL that pays the user's pending membership for the tier (made now if there is none).
      # Shopify not answering raises.
      def begin_purchase(user, tier_id)
        claim_pending(user, tier_id).checkout_link
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

    # The invoice URL that pays this membership, creating its draft order if there is none yet.
    def checkout_link
      # Faculty memberships never trigger Shopify calls
      return '/' if faculty?

      draft = fetch_or_create_draft
      draft = replace_draft(draft) if draft.nil? || reprice?(draft)
      draft['invoiceUrl'] || raise("Draft order #{shopify_draft_order_id} has no invoice URL")
    end

    private

    # The membership's Shopify draft order, made first if it has none; nil when Shopify says it no longer has it.
    def fetch_or_create_draft
      shopify_draft_order_id.blank? ? create_and_adopt_draft : fetch_stored_draft
    end

    def fetch_stored_draft
      state, draft = fetch_shopify_draft_order_result
      raise 'Shopify did not answer the draft order check' if state == :error

      draft
    end

    # The draft just created is served from the answer to its own creation: a read straight after it may not see it
    # yet. When another request adopted a draft first, this one's is deleted and the winner's is read.
    def create_and_adopt_draft
      new_id, _, invoice_url = create_remote_draft_order
      created = { 'id' => new_id, 'invoiceUrl' => invoice_url, 'status' => 'OPEN' }
      return created if keep_or_discard_draft(new_id)

      # The winner's draft may be as new as ours: if Shopify does not show it yet, ask again rather than replace it.
      raise "Membership #{id} has no draft order to serve" if shopify_draft_order_id.blank?

      fetch_stored_draft || raise("Draft order #{shopify_draft_order_id} is not on Shopify yet")
    end

    # A payable draft whose line was priced differently from what the tier charges this member now. A draft that
    # does not say its price is taken as current. A completed draft (paid, order not applied yet) is never replaced:
    # a second payable draft would let the member pay twice.
    def reprice?(draft)
      price = draft_price(draft)
      ShopifyConcern::DraftRemoval.payable?(draft) && price.present? && BigDecimal(price) != membership_tier.price(user)
    end

    def draft_price(draft)
      draft.dig('lineItems', 'nodes')&.first&.dig('originalUnitPriceSet', 'shopMoney', 'amount')
    end

    # Swaps the draft Shopify no longer has, or has at an out-of-date price (`draft`), for one at today's price,
    # keeping one payable draft at all times: the old draft is deleted first (a draft reported gone is deleted too,
    # in case the read was wrong), and only when Shopify confirms it gone is its id released and a new draft made.
    # If the old draft cannot be deleted (reported) the member keeps it and pays the price its open invoice shows.
    def replace_draft(draft)
      stale_id = shopify_draft_order_id
      unless delete_draft(stale_id, 'stale')
        return draft || raise("Draft order #{stale_id} is gone from Shopify but could not be released")
      end

      change_if_pending({ shopify_draft_order_id: stale_id }, shopify_draft_order_id: nil)
      reload
      fetch_or_create_draft || raise("Draft order #{shopify_draft_order_id} is not on Shopify right after it was made")
    end

    # ShopifyConcern's hook for a draft it has just created.
    def store_shopify_draft_order_id(new_id, _line_items)
      keep_or_discard_draft(new_id)
    end

    # The draft was just created on Shopify (no lock held); keep it only if no other request stored one first. A
    # draft that lost the race, or could not be stored, is deleted, so one membership has one payable draft. True
    # when this draft was kept.
    def keep_or_discard_draft(new_id)
      kept = adopt_draft(new_id)
      discard_unused_draft(new_id) unless kept
      kept
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
      Rails.error.report(e, handled: true, severity: :error,
                            context: { membership_id: id, step: "delete_#{what}_shopify_draft_order" })
      false
    end
  end
end
