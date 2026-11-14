# frozen_string_literal: true

class Membership
  # Closes checkouts that were started and never paid. A pending membership is the checkout record and its Shopify draft
  # order is what the member pays; one nobody finishes would otherwise stay open and payable for ever. A pending
  # membership with no checkout activity for STALE_AFTER has its draft order deleted and is then marked expired. The
  # row is kept. Activity is the row's updated_at: it moves when a draft is stored and whenever the member starts the
  # purchase again (Membership.claim_pending), so a checkout the member has just come back to is never closed.
  #
  # A draft that is paid (completed) is never touched, and neither is its membership: the payment is applied to it as
  # usual. A draft already gone from Shopify counts as deleted. Shopify's draft delete is idempotent by nature (a
  # second delete of the same draft only reports it gone), so a run can be repeated safely. The change of status is a
  # conditional UPDATE from the state this run saw (Membership#change_if_pending), so a payment, or a member who
  # buys again, while a run is in progress is not overwritten.
  module Expiry
    extend ActiveSupport::Concern

    # A pending membership untouched this long is no longer a checkout in progress. Seven days is long enough for a
    # member to come back to a checkout they left, and short enough that unpaid drafts do not pile up on Shopify.
    STALE_AFTER = 7.days

    class_methods do
      def stale_pending(cutoff = STALE_AFTER.ago)
        pending.where(updated_at: ...cutoff)
      end

      # Expires every stale pending membership. Returns how many ended in each outcome:
      # :expired, :paid (left alone: its draft is paid), :open (the draft could not be deleted), :changed (the
      # membership changed while the run was in progress), :error (reported; tried again by the next run).
      def expire_stale_pending!
        stale_pending.find_each.map(&:expire_if_stale).tally
      end
    end

    # Deletes the draft order and marks this membership expired, if it is still stale. Returns the outcome named above.
    def expire_if_stale
      cutoff = STALE_AFTER.ago
      return :changed unless self.class.stale_pending(cutoff).exists?(id: id)

      gid = shopify_draft_order_id
      outcome = remove_stale_draft(gid)
      return outcome unless outcome == :removed

      change_if_pending({ shopify_draft_order_id: gid, updated_at: ...cutoff }, status: 'expired') ? :expired : :changed
    rescue StandardError => e
      # One membership that cannot be settled (Shopify down, a refused call) must not stop the others: it is reported
      # and stays pending, and the next run tries it again. Shopify's errors share no base class to narrow this to.
      Rails.error.report(e, handled: true, severity: :error,
                            context: { membership_id: id, step: 'expire_stale_pending' })
      :error
    end

    private

    # :removed when no payable draft is left, :paid when the draft is paid, :open when it is still payable.
    def remove_stale_draft(gid)
      return :removed if gid.blank?

      state, draft = Payments::ShopifyAdapter::DraftRemoval.fetch_or_raise(gid)
      return :removed if state == :gone
      return :paid if Payments::ShopifyAdapter::DraftRemoval.paid?(draft)

      removal_outcome(Payments::ShopifyAdapter::DraftRemoval.call(gid).outcome)
    end

    def removal_outcome(outcome)
      case outcome
      when :deleted, :gone then :removed
      when :completed then :paid
      else :open
      end
    end
  end
end
