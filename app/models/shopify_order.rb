# frozen_string_literal: true

# One payment-provider order whose webhook has been applied (see CreateShopifyOrders). The row is the claim:
# a delivery that inserts it applies the order, one that finds it already there applies nothing. Never updated
# or deleted.
class ShopifyOrder < ApplicationRecord
  PROVIDER = "shopify"

  # Claims the order with INSERT ... ON CONFLICT DO NOTHING. True when this call inserted the row; false when
  # the order was already claimed. Meant to run inside the transaction that applies the order: a concurrent
  # delivery of the same order waits on the unique index until that transaction ends, then finds the row (it
  # committed) or inserts its own (it rolled back), so a failure after the claim releases it.
  def self.claim!(ref, topic:, name: nil)
    insert_all([{ provider: PROVIDER, provider_ref: ref.to_s, topic: topic, order_name: name.presence&.to_s&.first(64) }],
               unique_by: %i[provider provider_ref]).rows.any?
  end
end
