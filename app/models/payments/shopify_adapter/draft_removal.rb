# frozen_string_literal: true

module Payments
  class ShopifyAdapter
    # THE rule for taking a Shopify draft order away by its gid, shared by JobOrder (JobOrder::DraftDeletion),
    # LockerRental, Membership and #cancel_checkout. It only talks to Shopify and classifies (DraftOrders is the raw
    # delete/fetch under it, DraftStatus reads the status); it changes no record: each caller decides what the outcome means for its own stored id
    # and for its own failure path.
    #
    #   DraftRemoval.call(gid) -> Result(outcome, user_errors)
    #     :deleted    Shopify confirmed the delete (deletedId)
    #     :gone       Shopify refused (a 200 with userErrors and no deletedId) and a fetch shows the draft no longer exists
    #     :completed  Shopify refused and the draft is COMPLETED: it is paid, it became an order, nothing to remove
    #     :open       Shopify refused and the draft is still there, unpaid: a real failure
    #   Raises DraftOrders::Unanswered when the follow-up fetch gets no answer, and propagates any HTTP/config exception: the caller
    #   never learns "gone" or "paid" from an error.
    module DraftRemoval
      Result = Struct.new(:outcome, :user_errors)

      def self.call(gid)
        user_errors = []
        return Result.new(:deleted, user_errors) if DraftOrders.delete(gid, user_errors_out: user_errors)

        state, draft = DraftOrders.fetch_or_raise(gid)
        return Result.new(:gone, user_errors) if state == :gone

        Result.new(DraftStatus.paid?(draft) ? :completed : :open, user_errors)
      end
    end
  end
end
