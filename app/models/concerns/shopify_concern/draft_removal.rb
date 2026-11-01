# frozen_string_literal: true

# THE rule for taking a Shopify draft order away by its gid, shared by JobOrder (JobOrder::DraftDeletion) and
# LockerRental. It lives under ShopifyConcern because that is the Shopify-facing layer both already sit on
# (ShopifyConcern::DraftOrders is the raw delete/fetch under it); it only talks to Shopify and classifies, it
# changes no record: each caller decides what the outcome means for its own stored id and for its own failure path.
#
#   ShopifyConcern::DraftRemoval.call(gid) -> Result(outcome, user_errors)
#     :deleted    Shopify confirmed the delete (deletedId)
#     :gone       Shopify refused (a 200 with userErrors and no deletedId) and a fetch shows the draft no longer exists
#     :completed  Shopify refused and the draft is COMPLETED: it is paid, it became an order, nothing to remove
#     :open       Shopify refused and the draft is still there, unpaid: a real failure
#   Raises Unanswered when the follow-up fetch gets no answer, and propagates any HTTP/config exception: the caller
#   never learns "gone" or "paid" from an error.
module ShopifyConcern
  module DraftRemoval
    Result = Struct.new(:outcome, :user_errors)

    # Shopify did not answer the check that follows a refused delete.
    class Unanswered < StandardError; end

    # Shopify's DraftOrderStatus: COMPLETED is paid (the draft became an order).
    PAID_STATUS = "COMPLETED"

    module_function

    def paid?(draft) = draft["status"] == PAID_STATUS

    # [:found | :gone, draft]; Shopify not answering raises Unanswered.
    def fetch_or_raise(gid)
      state, draft = ShopifyConcern::DraftOrders.fetch_result(gid)
      raise Unanswered, "Shopify did not answer the draft order check" if state == :error

      [state, draft]
    end

    def call(gid)
      user_errors = []
      return Result.new(:deleted, user_errors) if ShopifyConcern::DraftOrders.delete(gid, user_errors_out: user_errors)

      state, draft = fetch_or_raise(gid)
      return Result.new(:gone, user_errors) if state == :gone

      Result.new(paid?(draft) ? :completed : :open, user_errors)
    end
  end
end
