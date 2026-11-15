# frozen_string_literal: true

module Payments
  class ShopifyAdapter
    # What a Shopify draft's DraftOrderStatus means (`draft` is a fetched or listed draft node).
    module DraftStatus
      # COMPLETED is paid (the draft became an order).
      PAID = "COMPLETED"
      # OPEN and INVOICE_SENT drafts are unpaid and payable (the invoice link works). The only statuses a link is served for.
      PAYABLE = %w[OPEN INVOICE_SENT].freeze

      module_function

      def paid?(draft) = draft["status"] == PAID

      def payable?(draft) = PAYABLE.include?(draft["status"])
    end
  end
end
