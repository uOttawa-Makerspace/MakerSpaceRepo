# frozen_string_literal: true

class Membership
  # Closes checkouts that were started and never paid. A pending membership is the checkout record and its Shopify draft
  # order is what the member pays; one nobody finishes would otherwise stay open and payable for ever. A pending
  # membership older than STALE_AFTER has its draft order deleted and is then marked failed. The row is kept.
  #
  # A draft that is paid (completed) is never touched, and neither is its membership: the payment is applied to it as
  # usual. A draft already gone from Shopify counts as deleted. Shopify's draft delete is idempotent by nature (a
  # second delete of the same draft only reports it gone), so a run can be repeated safely. The change of status is a
  # conditional UPDATE from the state this run saw (Membership#change_if_pending), so a member who buys again, or a
  # payment that arrives, while a run is in progress is not overwritten.
  module Expiry
    extend ActiveSupport::Concern

    # A pending membership this old is no longer a checkout in progress.
    STALE_AFTER = 7.days

    # What deleting a draft means for the membership it belongs to (see ShopifyConcern::DraftRemoval).
    DRAFT_OUTCOMES = { deleted: :removed, gone: :removed, completed: :paid, open: :open }.freeze

    class_methods do
      def stale_pending
        pending.where(created_at: ...STALE_AFTER.ago)
      end

      # Expires every stale pending membership. Returns how many ended in each outcome:
      # :expired, :paid (left alone: its draft is paid), :open (the draft could not be deleted), :changed (the
      # membership changed while the run was in progress), :error (reported; tried again by the next run).
      def expire_stale_pending!
        stale_pending.find_each.map(&:expire_stale).tally
      end
    end

    # Deletes the draft order and marks this membership failed. Returns the outcome named above.
    def expire_stale
      gid = shopify_draft_order_id
      outcome = remove_stale_draft(gid)
      return outcome unless outcome == :removed

      change_if_pending({ shopify_draft_order_id: gid }, status: 'failed') ? :expired : :changed
    rescue StandardError => e
      Rails.error.report(e, handled: true, severity: :error,
                            context: { membership_id: id, step: 'expire_stale_pending' })
      :error
    end

    private

    # :removed when no payable draft is left, :paid when the draft is paid, :open when it is still payable.
    def remove_stale_draft(gid)
      return :removed if gid.blank?

      state, draft = ShopifyConcern::DraftRemoval.fetch_or_raise(gid)
      return :removed if state == :gone
      return :paid if ShopifyConcern::DraftRemoval.paid?(draft)

      DRAFT_OUTCOMES.fetch(ShopifyConcern::DraftRemoval.call(gid).outcome)
    end
  end
end
