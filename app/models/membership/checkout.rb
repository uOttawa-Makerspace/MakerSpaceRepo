# frozen_string_literal: true

class Membership
  # A member's purchase of a tier: the pending membership is the checkout record, and its Shopify draft order is what
  # the member pays. At most one pending membership exists per member and tier, and a pending membership has at most
  # one payable draft at any moment.
  #
  # Concurrency: the user's row lock serializes claiming a pending membership (Shopify itself is called outside any
  # lock). A new draft is stored under the membership's row lock, read again, only while the membership is pending
  # and has none (#keep_draft_order_id_unless_taken); every other change to its draft id or status is a
  # conditional UPDATE from the state the caller saw (Membership#change_if_pending), so a request holding an
  # out-of-date view of the row changes nothing and releases only the draft it deleted. A draft that loses such a
  # race is deleted, and the loser serves the winner's draft.
  module Checkout
    extend ActiveSupport::Concern

    # The membership was closed (no longer pending) while its checkout was being made.
    class CheckoutClosed < StandardError; end

    class_methods do
      # Member and tier pairs that have more than one pending membership, as [user_id, tier_id, [membership ids]],
      # ordered by member, then tier, with the ids ascending. Reads only.
      def pending_duplicates
        pending.group(:user_id, :membership_tier_id).having('count(*) > 1').order(:user_id, :membership_tier_id)
               .pluck(:user_id, :membership_tier_id, Arel.sql('array_agg(id ORDER BY id)'))
      end

      # The Shopify invoice URL that pays the user's pending membership for the tier (made now if there is none).
      # Shopify not answering raises.
      def begin_purchase(user, tier_id)
        claim_pending(user, tier_id).checkout_link
      rescue CheckoutClosed
        # The membership was closed (expired) after it was claimed and before its draft could be stored: the next
        # claim cannot return it, so this one starts a new pending membership.
        claim_pending(user, tier_id).checkout_link
      end

      # The user's pending membership for the tier, or a new one. Under the user's row lock, so repeated or
      # simultaneous purchases share one row. A pending membership has no dates: they are set when it is paid. A
      # reused row is touched: buying again is checkout activity, so it is not expired while the member uses it.
      def claim_pending(user, tier_id)
        user.with_lock do
          existing = user.memberships.pending.where(membership_tier_id: tier_id).order(:id).first
          existing&.touch
          existing || user.memberships.create!(membership_tier_id: tier_id)
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
      return created if keep_draft_order_id_unless_taken(new_id)

      raise CheckoutClosed, "Membership #{id} was expired while its draft was being made" if expired?
      # The winner's draft may be as new as ours: if Shopify does not show it yet, ask again rather than replace it.
      raise "Membership #{id} has no draft order to serve" if shopify_draft_order_id.blank?

      fetch_stored_draft || raise("Draft order #{shopify_draft_order_id} is not on Shopify yet")
    end

    # A payable draft whose line was priced differently from what the tier charges this member now. A draft that
    # does not say its price is taken as current. A completed draft (paid, order not applied yet) is never replaced:
    # a second payable draft would let the member pay twice.
    def reprice?(draft)
      price = draft_price(draft)
      Payments::ShopifyAdapter::DraftRemoval.payable?(draft) && price.present? && BigDecimal(price) != membership_tier.price(user)
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
      unless delete_stale_draft(stale_id)
        return draft || raise("Draft order #{stale_id} is gone from Shopify but could not be released")
      end

      change_if_pending({ shopify_draft_order_id: stale_id }, shopify_draft_order_id: nil)
      reload
      fetch_or_create_draft || raise("Draft order #{shopify_draft_order_id} is not on Shopify right after it was made")
    end

    # Read under the row lock by #keep_draft_order_id_unless_taken: only a pending membership takes a new draft.
    def may_take_draft_order? = pending?

    # Storing a new draft is checkout activity, so the pending membership is not expired while the member pays.
    def store_shopify_draft_order_id(new_id)
      update_columns(shopify_draft_order_id: new_id, updated_at: Time.current)
    end

    # Deletes the stored draft on Shopify. True when it is deleted or gone. False when it was paid meanwhile, and
    # false (reported) when it is still open or Shopify could not be asked: the draft is then still payable.
    def delete_stale_draft(gid)
      outcome = Payments::ShopifyAdapter::DraftRemoval.call(gid).outcome
      raise "Shopify did not delete the stale draft order #{gid}" if outcome == :open

      outcome != :completed
    rescue StandardError => e
      Rails.error.report(e, handled: true, severity: :error,
                            context: { membership_id: id, step: 'delete_stale_shopify_draft_order' })
      false
    end
  end
end
