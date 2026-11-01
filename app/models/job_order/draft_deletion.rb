# frozen_string_literal: true

# The ONLY code that deletes a Shopify draft by gid for a job order, and the one rule for a delete Shopify refuses.
# Private to JobOrder (JobOrder.private_constant): only JobOrder and JobOrder::DraftSweep, which both lexically sit
# inside it, can name it. #delete_unless_completed! checks the fetched draft's marker (this environment's operating
# tag and exactly the given order's marker) unless the caller opts out with `marker: nil` (an order's own stored
# draft, which may predate the marker); #delete itself checks nothing, so nothing outside JobOrder may reach it
# (ShopifyConcern::DraftRemoval is the shared delete-and-classify rule under it, shared with LockerRental).
class JobOrder
  module DraftDeletion
    module_function

    # The one fail-closed conversion for Shopify work behind a status decision: any error (HTTP, timeout, session,
    # configuration) becomes StaleDraftOrderError, so the caller refuses and its transaction rolls back. A database
    # error is not Shopify's: it propagates as itself.
    def fail_closed
      yield
    rescue StaleDraftOrderError, ActiveRecord::ActiveRecordError
      raise
    rescue StandardError => e
      raise StaleDraftOrderError, "#{e.class}: #{e.message}"
    end

    # [:found | :gone, draft]; Shopify not answering raises (fail closed).
    def fetch_or_raise(gid)
      ShopifyConcern::DraftRemoval.fetch_or_raise(gid)
    rescue ShopifyConcern::DraftRemoval::Unanswered => e
      JobOrder.stale_draft!(e.message)
    end

    # Deletes the draft `gid` (one Shopify call) and returns :deleted. When Shopify deleted nothing it is asked why
    # by the shared rule (ShopifyConcern::DraftRemoval, which classifies): the draft vanished (:cleared), or it is
    # paid (COMPLETED), which `paid` decides: :keep returns :kept (the payment record is never deleted), :refuse
    # raises (the caller is mid-transition and must not go on). Anything else raises StaleDraftOrderError with
    # Shopify's userErrors.
    def delete(gid, paid:)
      result = begin
        ShopifyConcern::DraftRemoval.call(gid)
      rescue ShopifyConcern::DraftRemoval::Unanswered => e
        JobOrder.stale_draft!(e.message)
      end

      case result.outcome
      when :deleted then :deleted
      when :gone then :cleared
      when :completed
        return :kept if paid == :keep

        JobOrder.stale_draft!("the draft order is already paid (COMPLETED)")
      else JobOrder.not_deleted_by_shopify!(result.user_errors)
      end
    end

    # The paid-settle rule for a draft `gid`, whoever (if anyone) points at it: [:cleared] Shopify no longer has it,
    # [:kept] it is paid, [:deleted]. Fetch first, so a paid draft is never sent a delete. Fail closed.
    # `marker`: the order id the draft must be marked for: the fetched draft must carry THIS environment's operating
    # tag and exactly that order's marker (JobOrder.draft_marker_order_id), else it is refused and nothing is deleted.
    # nil opts out explicitly: only for an order's own stored draft, which may predate the marker.
    def delete_unless_completed!(gid, marker:)
      fail_closed do
        state, draft = fetch_or_raise(gid)
        next :cleared if state == :gone

        if marker && !JobOrder.marked_for?(draft["tags"], marker)
          JobOrder.stale_draft!("the draft order is not marked for job order ##{marker} of this environment")
        end
        next :kept if JobOrder.draft_paid?(draft)

        unless JobOrder::PAYABLE_DRAFT_STATUSES.include?(draft["status"])
          JobOrder.stale_draft!("the draft order has the unknown status #{draft['status'].inspect}")
        end
        delete(gid, paid: :keep)
      end
    end
  end
end
