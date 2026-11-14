# frozen_string_literal: true

module Payments
  # What a payment is for, in provider-neutral terms: the kind of product ("locker", "membership", "job_order"), the
  # id of the record that is paid, and optionally the id of the checkout record (a stable key that lets a retried
  # create find the checkout an earlier attempt made, see ShopifyAdapter#find_open_checkout).
  Reference = Data.define(:kind, :record_id, :checkout_id) do
    def initialize(kind:, record_id: nil, checkout_id: nil)
      super(kind: kind.to_s, record_id: record_id, checkout_id: checkout_id)
    end
  end
end
