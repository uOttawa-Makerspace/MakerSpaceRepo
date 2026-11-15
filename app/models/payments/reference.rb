# frozen_string_literal: true

module Payments
  # What a payment is for, in provider-neutral terms: the kind of product (one of KINDS), the id of the record that is
  # paid, and optionally the integer id of the checkout record (a stable key that lets a retried create find the
  # checkout an earlier attempt made, see ShopifyAdapter#find_open_checkout). Raises ArgumentError for an unknown kind
  # or a checkout id that is not an Integer.
  Reference = Data.define(:kind, :record_id, :checkout_id) do
    def initialize(kind:, record_id: nil, checkout_id: nil)
      raise ArgumentError, "unknown reference kind #{kind.inspect}" unless self.class::KINDS.include?(kind.to_s)
      raise ArgumentError, "the checkout id must be an Integer" unless checkout_id.nil? || checkout_id.is_a?(Integer)

      super(kind: kind.to_s, record_id: record_id, checkout_id: checkout_id)
    end
  end

  # The product kinds a payment can be for: the products a checkout is made for (each model's
  # shopify_draft_order_key_name), and CC Money, bought in the shop.
  Reference::KINDS = %w[locker membership job_order cc_money].freeze
end
