# frozen_string_literal: true

# The ONLY code that deletes a Shopify draft by gid for a job order, and the one rule for a delete Shopify refuses.
# Private to JobOrder (JobOrder.private_constant): only JobOrder and JobOrder::DraftSweep, which both lexically sit
# inside it, can name it. It does not check the draft's tags or its owner, so nothing outside JobOrder may reach it
# (ShopifyConcern::DraftOrders.delete is the raw call under it; see the note there).
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
      state, draft = ShopifyConcern::DraftOrders.fetch_result(gid)
      JobOrder.stale_draft!("Shopify did not answer the draft order check") if state == :error

      [state, draft]
    end

    # Deletes the draft `gid` (one Shopify call) and returns :deleted. When Shopify deleted nothing it is asked why
    # (THE refused-delete rule): the draft vanished (:cleared), or it is paid (COMPLETED), which `paid` decides:
    # :keep returns :kept (the payment record is never deleted), :refuse raises (the caller is mid-transition and
    # must not go on). Anything else raises StaleDraftOrderError with Shopify's userErrors.
    def delete(gid, paid:)
      user_errors = []
      return :deleted if ShopifyConcern::DraftOrders.delete(gid, user_errors_out: user_errors)

      state, draft = fetch_or_raise(gid)
      return :cleared if state == :gone

      if JobOrder.draft_paid?(draft)
        return :kept if paid == :keep

        JobOrder.stale_draft!("the draft order is already paid (COMPLETED)")
      end
      JobOrder.not_deleted_by_shopify!(user_errors)
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
